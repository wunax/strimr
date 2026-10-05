import Foundation
@testable import Strimr
import Testing

@MainActor
struct ProfileStoreTests {
    private let defaults = TestDefaults.make()

    private let plexAccount = MediaAccount.plex(PlexAccount(id: "owner", displayName: "Owner"))
    private let jellyfinAccount = MediaAccount.jellyfin(JellyfinAccount(connection: JellyfinConnection(
        baseURL: URL(string: "https://jellyfin.example.invalid")!,
        serverID: "jf-server",
        serverName: "Jellyfin",
        serverVersion: "10.10.0",
        userID: "jf-user",
        username: "alice",
    )))

    private var accounts: [MediaAccount] {
        [plexAccount, jellyfinAccount]
    }

    @Test func `local and plex home profiles are listed together`() {
        let store = ProfileStore(userDefaults: defaults)
        let local = store.createLocalProfile(name: "Kids")
        store.updatePlexHomeUsers([homeUser("owner"), homeUser("guest")], accountID: plexAccount.id)

        #expect(store.profiles(accounts: accounts).map(\.id) == [local.id, "plex.owner", "plex.guest"])
    }

    @Test func `a home user shared by two accounts is listed once`() {
        let store = ProfileStore(userDefaults: defaults)
        let second = MediaAccount.plex(PlexAccount(id: "second", displayName: "Second"))
        store.updatePlexHomeUsers([homeUser("owner")], accountID: plexAccount.id)
        store.updatePlexHomeUsers([homeUser("owner"), homeUser("friend")], accountID: second.id)

        let profiles = store.profiles(accounts: [plexAccount, second])

        #expect(profiles.map(\.id) == ["plex.owner", "plex.friend"])
        #expect(profiles.first?.plexHomeProfile?.accountID == plexAccount.id)
    }

    @Test func `plex home profiles are implicitly linked to their account`() throws {
        let store = ProfileStore(userDefaults: defaults)
        store.updatePlexHomeUsers([homeUser("owner")], accountID: plexAccount.id)
        let profile = try #require(store.profile(id: "plex.owner", accounts: accounts))

        store.addLink(ProfileLink(
            profileID: profile.id,
            accountID: jellyfinAccount.id,
            user: .jellyfin(userID: "jf-user"),
        ))

        #expect(store.links(for: profile) == [
            ProfileLink(profileID: "plex.owner", accountID: plexAccount.id, user: .plexHome(uuid: "owner")),
            ProfileLink(profileID: "plex.owner", accountID: jellyfinAccount.id, user: .jellyfin(userID: "jf-user")),
        ])
        #expect(!store.state.links.contains { $0.accountID == plexAccount.id })
    }

    @Test func `a local profile without links cannot be activated`() {
        let store = ProfileStore(userDefaults: defaults)
        let profile = StrimrProfile.local(store.createLocalProfile(name: "Empty"))

        #expect(!store.hasLinks(profile))
    }

    @Test func `local profile pins are hashed`() throws {
        let store = ProfileStore(userDefaults: defaults)
        let profile = store.createLocalProfile(name: "Locked", pin: "1234")
        let pin = try #require(profile.pin)

        #expect(pin.verify("1234"))
        #expect(!pin.verify("0000"))
        #expect(pin.hash != "1234")
        let stored = String(decoding: defaults.data(forKey: ProfileStore.storageKey) ?? Data(), as: UTF8.self)
        #expect(!stored.contains("\"1234\""))
    }

    @Test func `a new link enables every server of its account`() {
        let store = ProfileStore(userDefaults: defaults)
        let profile = store.createLocalProfile(name: "Kids")
        store.setDefaultServerSelection(.only(["server-a"]), accountID: plexAccount.id)

        store.addLink(ProfileLink(profileID: profile.id, accountID: plexAccount.id, user: .plexHome(uuid: "kid")))

        #expect(store.isServerEnabled("server-b", profileID: profile.id, accountID: plexAccount.id))
    }

    @Test func `server activation is per profile`() {
        let store = ProfileStore(userDefaults: defaults)

        store.setServer("server-a", enabled: false, profileID: "plex.owner", accountID: plexAccount.id)

        #expect(!store.isServerEnabled("server-a", profileID: "plex.owner", accountID: plexAccount.id))
        #expect(store.isServerEnabled("server-a", profileID: "plex.guest", accountID: plexAccount.id))
        #expect(store.isServerEnabled("server-b", profileID: "plex.owner", accountID: plexAccount.id))
    }

    @Test func `profiles without a choice follow the account default`() {
        let store = ProfileStore(userDefaults: defaults)
        store.setDefaultServerSelection(.only(["server-a"]), accountID: plexAccount.id)

        store.setServer("server-b", enabled: true, profileID: "plex.owner", accountID: plexAccount.id)

        #expect(store.isServerEnabled("server-b", profileID: "plex.owner", accountID: plexAccount.id))
        #expect(store.isServerEnabled("server-a", profileID: "plex.owner", accountID: plexAccount.id))
        #expect(!store.isServerEnabled("server-b", profileID: "plex.guest", accountID: plexAccount.id))
    }

    @Test func `deleting a local profile removes its links and keeps the accounts`() {
        let store = ProfileStore(userDefaults: defaults)
        let profile = store.createLocalProfile(name: "Kids")
        store.addLink(ProfileLink(
            profileID: profile.id,
            accountID: jellyfinAccount.id,
            user: .jellyfin(userID: "jf-user"),
        ))
        store.setServer("jf-server", enabled: false, profileID: profile.id, accountID: jellyfinAccount.id)
        store.setActiveProfile(profile.id)

        store.deleteLocalProfile(id: profile.id)

        #expect(store.state.localProfiles.isEmpty)
        #expect(store.state.links.isEmpty)
        #expect(store.state.serverSelections[profile.id] == nil)
        #expect(store.activeProfileID == nil)
        #expect(store.profileIDs(using: jellyfinAccount.id, accounts: accounts).isEmpty)
    }

    @Test func `removed home users are cleaned up only by a successful load`() {
        let store = ProfileStore(userDefaults: defaults)
        store.updatePlexHomeUsers([homeUser("owner"), homeUser("kid")], accountID: plexAccount.id)
        store.addLink(ProfileLink(
            profileID: "plex.kid",
            accountID: jellyfinAccount.id,
            user: .jellyfin(userID: "jf-user"),
        ))

        // A failed load never calls the store, so the kid keeps its links.
        #expect(store.profiles(accounts: accounts).map(\.id) == ["plex.owner", "plex.kid"])

        let removed = store.updatePlexHomeUsers([homeUser("owner")], accountID: plexAccount.id)

        #expect(removed == ["plex.kid"])
        #expect(store.profiles(accounts: accounts).map(\.id) == ["plex.owner"])
        #expect(store.state.links.isEmpty)
    }

    @Test func `borrowing lists each connection once without servers already linked`() throws {
        let store = ProfileStore(userDefaults: defaults)
        let otherJellyfinUser = try MediaAccount.jellyfin(JellyfinAccount(connection: JellyfinConnection(
            baseURL: #require(URL(string: "https://jellyfin.example.invalid")),
            serverID: "jf-server",
            serverName: "Jellyfin",
            serverVersion: "10.10.0",
            userID: "jf-bob",
            username: "bob",
        )))
        let thirdServer = try MediaAccount.jellyfin(JellyfinAccount(connection: JellyfinConnection(
            baseURL: #require(URL(string: "https://other.example.invalid")),
            serverID: "jf-other",
            serverName: "Other",
            serverVersion: "10.10.0",
            userID: "jf-carol",
            username: "carol",
        )))
        let allAccounts = [plexAccount, jellyfinAccount, otherJellyfinUser, thirdServer]
        store.updatePlexHomeUsers([homeUser("owner"), homeUser("guest")], accountID: plexAccount.id)
        let alice = store.createLocalProfile(name: "Alice")
        let bob = store.createLocalProfile(name: "Bob")
        let target = store.createLocalProfile(name: "Target")
        store.addLink(ProfileLink(
            profileID: alice.id,
            accountID: jellyfinAccount.id,
            user: .jellyfin(userID: "jf-user"),
        ))
        store.addLink(ProfileLink(profileID: bob.id, accountID: jellyfinAccount.id, user: .jellyfin(userID: "jf-user")))
        store.addLink(ProfileLink(profileID: bob.id, accountID: thirdServer.id, user: .jellyfin(userID: "jf-carol")))
        store.addLink(ProfileLink(
            profileID: target.id,
            accountID: otherJellyfinUser.id,
            user: .jellyfin(userID: "jf-bob"),
        ))
        let profile = try #require(store.profile(id: target.id, accounts: allAccounts))

        let borrowable = store.borrowableConnections(for: profile, accounts: allAccounts)

        // jf-server is already reached by the target through bob's account; the two Plex Home users are two entries.
        #expect(Set(borrowable.map(\.id)) == [
            "jellyfin:jf-other.jf-carol|jf-carol",
            "plex:owner|owner",
            "plex:owner|guest",
        ])
    }

    @Test func `a plex account already linked is not offered again`() throws {
        let store = ProfileStore(userDefaults: defaults)
        store.updatePlexHomeUsers([homeUser("owner"), homeUser("guest")], accountID: plexAccount.id)
        let profile = try #require(store.profile(id: "plex.guest", accounts: [plexAccount]))

        #expect(store.borrowableConnections(for: profile, accounts: [plexAccount]).isEmpty)
    }

    @Test func `jellyfin accounts no profile uses can be linked`() throws {
        let store = ProfileStore(userDefaults: defaults)
        store.updatePlexHomeUsers([homeUser("owner")], accountID: plexAccount.id)
        let target = store.createLocalProfile(name: "Target")
        let profile = try #require(store.profile(id: target.id, accounts: accounts))

        let borrowable = store.borrowableConnections(for: profile, accounts: accounts)

        let unused = try #require(borrowable.first { $0.sourceProfile == nil })
        #expect(unused.id == "jellyfin:jf-server.jf-user|jf-user")
        #expect(borrowable.count == 2)
    }

    @Test func `the jellyfin accounts left without any profile get one`() throws {
        let store = ProfileStore(userDefaults: defaults)
        let otherJellyfinUser = try MediaAccount.jellyfin(JellyfinAccount(connection: JellyfinConnection(
            baseURL: #require(URL(string: "https://jellyfin.example.invalid")),
            serverID: "jf-server",
            serverName: "Jellyfin",
            serverVersion: "10.10.0",
            userID: "jf-bob",
            username: "bob",
        )))
        store.updatePlexHomeUsers([homeUser("owner")], accountID: plexAccount.id)
        store.addLink(ProfileLink(
            profileID: "plex.owner",
            accountID: jellyfinAccount.id,
            user: .jellyfin(userID: "jf-user"),
        ))
        #expect(store.makeProfileForJellyfinAccounts(accounts: accounts) == nil)

        store.removeAccount(plexAccount.id)
        let remaining = [jellyfinAccount, otherJellyfinUser]
        let fallback = try #require(store.makeProfileForJellyfinAccounts(accounts: remaining))

        #expect(fallback.name == "alice")
        // One link per server: bob, on the same server, stays available to another profile.
        #expect(store.state.links == [ProfileLink(
            profileID: fallback.id,
            accountID: jellyfinAccount.id,
            user: .jellyfin(userID: "jf-user"),
        )])
        #expect(store.makeProfileForJellyfinAccounts(accounts: remaining) == nil)
    }

    @Test func `removing an account forgets it for every profile`() {
        let store = ProfileStore(userDefaults: defaults)
        store.updatePlexHomeUsers([homeUser("owner")], accountID: plexAccount.id)
        let kids = store.createLocalProfile(name: "Kids")
        store.addLink(ProfileLink(profileID: kids.id, accountID: plexAccount.id, user: .plexHome(uuid: "owner")))
        store.setDefaultServerSelection(.only(["server-a"]), accountID: plexAccount.id)
        store.setActiveProfile("plex.owner")

        store.removeAccount(plexAccount.id)

        #expect(store.state.links.isEmpty)
        #expect(store.state.serverSelections[kids.id]?[plexAccount.id] == nil)
        #expect(store.state.defaultServerSelections.isEmpty)
        #expect(store.profiles(accounts: [jellyfinAccount]).map(\.id) == [kids.id])
        #expect(store.activeProfileID == nil)
    }

    @Test func `watchlist comes from the parent account unless another was chosen`() throws {
        let store = ProfileStore(userDefaults: defaults)
        let second = MediaAccount.plex(PlexAccount(id: "second", displayName: "Second"))
        let allAccounts = [plexAccount, second, jellyfinAccount]
        store.updatePlexHomeUsers([homeUser("owner")], accountID: plexAccount.id)
        let home = try #require(store.profile(id: "plex.owner", accounts: allAccounts))
        let local = StrimrProfile.local(store.createLocalProfile(name: "Kids"))
        store.addLink(ProfileLink(
            profileID: local.id,
            accountID: jellyfinAccount.id,
            user: .jellyfin(userID: "jf-user"),
        ))
        store.addLink(ProfileLink(profileID: local.id, accountID: second.id, user: .plexHome(uuid: "s")))

        #expect(store.watchlistAccountID(for: home, accounts: allAccounts) == plexAccount.id)
        #expect(store.watchlistAccountID(for: local, accounts: allAccounts) == second.id)

        store.addLink(ProfileLink(profileID: home.id, accountID: second.id, user: .plexHome(uuid: "s")))
        store.setWatchlistAccount(second.id, profileID: home.id)
        #expect(store.watchlistAccountID(for: home, accounts: allAccounts) == second.id)
    }

    @Test func `state survives a reload`() {
        let store = ProfileStore(userDefaults: defaults)
        let profile = store.createLocalProfile(name: "Kids")
        store.setActiveProfile(profile.id)
        store.setAsksProfileOnLaunch(true)

        let reloaded = ProfileStore(userDefaults: defaults)

        #expect(reloaded.state == store.state)
    }

    private func homeUser(_ uuid: String) -> PlexHomeUser {
        PlexHomeUser(
            id: nil,
            uuid: uuid,
            title: uuid,
            username: nil,
            email: nil,
            friendlyName: nil,
            thumb: nil,
            protected: nil,
            pin: nil,
        )
    }
}
