import Foundation
@testable import Strimr
import Testing

@MainActor
struct MultiServerMigrationTests {
    private let defaults = TestDefaults.make()
    private let secureStore = InMemorySecureStore()

    private let plexUser = PlexCloudUser(
        id: 7,
        uuid: "user-1",
        username: "owner",
        title: "Owner",
        friendlyName: "Owner Name",
        authToken: "",
        thumb: nil,
    )
    private let connection = JellyfinConnection(
        baseURL: URL(string: "https://jellyfin.example.invalid")!,
        serverID: "jf-server",
        serverName: "Jellyfin",
        serverVersion: "10.10.0",
        userID: "jf-user",
        username: "alice",
    )

    // MARK: - Plex

    @Test func `plex user with a chosen home user becomes that home profile`() async throws {
        let context = makeContext()
        legacyPlex(token: "home-token", serverID: "server-a")

        let outcome = await context.migration(resolving: plexUser).run()

        #expect(outcome == .migrated(profileID: "plex.user-1"))
        #expect(context.accounts.accounts == [.plex(PlexAccount(id: "user-1", displayName: "Owner Name"))])
        #expect(try context.accounts.token(forAccountID: "plex:user-1") == "home-token")
        #expect(context.accounts.homeToken(accountID: "plex:user-1", userUUID: "user-1") == "home-token")
        #expect(context.profiles.activeProfileID == "plex.user-1")
        #expect(context.profiles.state.localProfiles.isEmpty)
        #expect(context.profiles.profiles(accounts: context.accounts.accounts).map(\.id) == ["plex.user-1"])
    }

    @Test func `only the previous server is enabled, for every home profile`() async {
        let context = makeContext()
        legacyPlex(token: "token", serverID: "server-a")

        _ = await context.migration(resolving: plexUser).run()

        for profileID in ["plex.user-1", "plex.other-home-user"] {
            #expect(context.profiles.isServerEnabled("server-a", profileID: profileID, accountID: "plex:user-1"))
            #expect(!context.profiles.isServerEnabled("server-b", profileID: profileID, accountID: "plex:user-1"))
        }
    }

    @Test func `the previous server can start offline right after the update`() async {
        let context = makeContext()
        legacyPlex(token: "token", serverID: "server-a")
        let resource = PlexCloudResource(
            name: "Server A",
            clientIdentifier: "server-a",
            accessToken: "t",
            connections: [],
        )
        var migration = context.migration(resolving: plexUser)
        migration.legacyPlexResource = { resource }

        _ = await migration.run()

        #expect(context.accounts.cachedResources(userUUID: "user-1")?.map(\.clientIdentifier) == ["server-a"])
    }

    @Test func `plex user without a chosen home user becomes the owner profile`() async {
        let context = makeContext()
        defaults.set("plex", forKey: MultiServerMigration.LegacyKeys.provider)
        secureStore.values[MultiServerMigration.LegacyKeys.plexToken] = "owner-token"

        let outcome = await context.migration(resolving: plexUser).run()

        #expect(outcome == .migrated(profileID: "plex.user-1"))
        #expect(context.profiles.serverSelection(profileID: "plex.user-1", accountID: "plex:user-1") == .all)
    }

    @Test func `legacy keys are removed after a successful migration`() async {
        let context = makeContext()
        legacyPlex(token: "token", serverID: "server-a")

        _ = await context.migration(resolving: plexUser).run()

        #expect(defaults.string(forKey: MultiServerMigration.LegacyKeys.provider) == nil)
        #expect(defaults.string(forKey: MultiServerMigration.LegacyKeys.plexServerIdentifier) == nil)
        #expect(secureStore.values[MultiServerMigration.LegacyKeys.plexToken] == nil)
        #expect(defaults.integer(forKey: MultiServerMigration.versionKey) == MultiServerMigration.currentVersion)
    }

    @Test func `unreadable keychain keeps the old keys for the next launch`() async {
        let context = makeContext()
        legacyPlex(token: "token", serverID: "server-a")
        secureStore.failsReads = true

        let outcome = await context.migration(resolving: plexUser).run()

        #expect(outcome == .failed)
        #expect(context.accounts.accounts.isEmpty)
        #expect(defaults.string(forKey: MultiServerMigration.LegacyKeys.plexServerIdentifier) == "server-a")
        #expect(defaults.integer(forKey: MultiServerMigration.versionKey) == 0)

        secureStore.failsReads = false
        #expect(await context.migration(resolving: plexUser).run() == .migrated(profileID: "plex.user-1"))
    }

    @Test func `unreachable plex keeps the old keys for the next launch`() async {
        let context = makeContext()
        legacyPlex(token: "token", serverID: "server-a")
        let migration = context.migration { _ in throw URLError(.notConnectedToInternet) }

        #expect(await migration.run() == .failed)
        #expect(secureStore.values[MultiServerMigration.LegacyKeys.plexToken] == "token")
        #expect(context.accounts.accounts.isEmpty)
    }

    @Test func `migration is idempotent`() async {
        let context = makeContext()
        legacyPlex(token: "token", serverID: "server-a")
        context.settings.updateInterface { $0.hiddenLibraryIds = ["1"] }

        _ = await context.migration(resolving: plexUser).run()
        let accounts = context.accounts.accounts
        let state = context.profiles.state
        let settings = context.settings.settings

        #expect(await context.migration(resolving: plexUser).run() == .alreadyMigrated)
        #expect(context.accounts.accounts == accounts)
        #expect(context.profiles.state == state)
        #expect(context.settings.settings == settings)
    }

    @Test func `running again after an interrupted run changes nothing`() async {
        let context = makeContext()
        legacyPlex(token: "token", serverID: "server-a")
        context.settings.updateInterface { $0.navigationLibraryIds = ["1"] }
        _ = await context.migration(resolving: plexUser).run()
        let state = context.profiles.state
        let settings = context.settings.settings
        defaults.removeObject(forKey: MultiServerMigration.versionKey)

        _ = await context.migration(resolving: plexUser).run()

        #expect(context.profiles.state == state)
        #expect(context.settings.settings == settings)
    }

    @Test func `fresh install has nothing to migrate`() async {
        let context = makeContext()

        #expect(await context.migration(resolving: plexUser).run() == .nothingToMigrate)
        #expect(context.accounts.accounts.isEmpty)
        #expect(defaults.integer(forKey: MultiServerMigration.versionKey) == MultiServerMigration.currentVersion)
    }

    // MARK: - Jellyfin

    @Test func `jellyfin user gets a local profile named after the user`() async throws {
        let context = makeContext()
        legacyJellyfin(token: "jf-token")

        let outcome = await context.migration(resolving: plexUser).run()

        let profile = try #require(context.profiles.state.localProfiles.first)
        #expect(outcome == .migrated(profileID: profile.id))
        #expect(profile.name == "alice")
        #expect(context.profiles.activeProfileID == profile.id)
        #expect(context.profiles.state.links == [ProfileLink(
            profileID: profile.id,
            accountID: "jellyfin:jf-server.jf-user",
            user: .jellyfin(userID: "jf-user"),
        )])
        #expect(context.accounts.accounts == [.jellyfin(JellyfinAccount(connection: connection))])
        // The Jellyfin token keeps its Keychain key.
        #expect(secureStore.values["strimr.jellyfin.token.jf-server.jf-user"] == "jf-token")
        #expect(defaults.data(forKey: MultiServerMigration.LegacyKeys.jellyfinConnection) == nil)
    }

    @Test func `jellyfin without a token starts without an account`() async {
        let context = makeContext()
        legacyJellyfin(token: nil)

        #expect(await context.migration(resolving: plexUser).run() == .nothingToMigrate)
        #expect(context.accounts.accounts.isEmpty)
        #expect(context.profiles.state.localProfiles.isEmpty)
    }

    // MARK: - Settings

    @Test func `hidden and pinned libraries are prefixed with the previous server`() async {
        let context = makeContext()
        legacyPlex(token: "token", serverID: "server-a")
        context.settings.updateInterface {
            $0.hiddenLibraryIds = ["2", "5"]
            $0.navigationLibraryIds = ["3", "1"]
        }

        _ = await context.migration(resolving: plexUser).run()

        let server = ServerIdentity(provider: .plex, id: "server-a")
        let libraries = context.settings.libraryPreferences(profileID: "plex.user-1")
        #expect(libraries.hiddenLibraries == ["2", "5"].map { LibraryIdentity(server: server, libraryID: $0) })
        #expect(libraries.navigationLibraries == ["3", "1"].map { LibraryIdentity(server: server, libraryID: $0) })
        #expect(context.settings.interface.hiddenLibraryIds.isEmpty)
        #expect(context.settings.interface.navigationLibraryIds.isEmpty)
    }

    @Test func `home rows of the current scope move to the profile with merged ids`() async {
        let context = makeContext()
        legacyPlex(token: "token", serverID: "server-a")
        var current = HomeRowPreferences()
        current.orderedRowIDs = [
            "home:plex:server-a:hub:movies.recent::/hubs/1",
            "home:plex:server-a:continueWatching",
            "home:plex:server-a:hub:shows.recent::/hubs/2",
        ]
        current.hiddenRowIDs = ["home:plex:server-a:hub:shows.recent::/hubs/2"]
        var other = HomeRowPreferences()
        other.hiddenRowIDs = ["home:plex:server-z:continueWatching"]
        context.settings.updateInterface {
            $0.homeRowsByScope = ["plex|server-a|user-1": current, "plex|server-z|user-1": other]
            $0.multiServerSearchEnabled = false
        }

        _ = await context.migration(resolving: plexUser).run()

        let rows = context.settings.homeRowPreferences(profileID: "plex.user-1")
        #expect(rows.orderedRowIDs == [
            "home:plex:server-a:hub:movies.recent::/hubs/1",
            "home:continueWatching",
            "home:plex:server-a:hub:shows.recent::/hubs/2",
        ])
        #expect(rows.hiddenRowIDs == ["home:plex:server-a:hub:shows.recent::/hubs/2"])
        #expect(context.settings.interface.homeRowsByScope.isEmpty)
        #expect(context.settings.interface.multiServerSearchEnabled == nil)
    }

    @Test func `jellyfin next up id loses its server`() async throws {
        let context = makeContext()
        legacyJellyfin(token: "jf-token")
        var rows = HomeRowPreferences()
        rows.orderedRowIDs = ["home:jellyfin:jf-server:nextUp", "home:jellyfin:jf-server:continueWatching"]
        context.settings.updateInterface { $0.homeRowsByScope = ["jellyfin|jf-server|jf-user": rows] }

        _ = await context.migration(resolving: plexUser).run()

        let profileID = try #require(context.profiles.activeProfileID)
        #expect(context.settings.homeRowPreferences(profileID: profileID).orderedRowIDs == [
            "home:nextUp", "home:continueWatching",
        ])
    }

    @Test func `local plex favorites follow the migrated profile`() async {
        let context = makeContext()
        legacyPlex(token: "token", serverID: "server-a")
        let media = MediaItem(
            id: "10",
            identity: MediaIdentity(server: ServerIdentity(provider: .plex, id: "server-a"), itemID: "10"),
            guid: "plex://movie/10",
            summary: nil,
            title: "Example",
            type: .movie,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: [],
            year: nil,
            duration: nil,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: nil,
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            artworkCornerColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
        )
        context.favorites.setFavorite(
            true,
            snapshot: PlexFavoriteSnapshot(media: media, libraryID: nil, libraryTitle: nil),
            in: .plex(serverID: "server-a", profileID: "user-1"),
        )

        _ = await context.migration(resolving: plexUser).run()

        #expect(context.favorites.favorites(for: .plex(serverID: "server-a", profileID: "user-1")).isEmpty)
        #expect(context.favorites.favorites(for: .plex(serverID: "server-a", profileID: "plex.user-1")).map(\.id) == [
            "10",
        ])
    }

    // MARK: - Helpers

    private func legacyPlex(token: String, serverID: String) {
        defaults.set("plex", forKey: MultiServerMigration.LegacyKeys.provider)
        defaults.set(serverID, forKey: MultiServerMigration.LegacyKeys.plexServerIdentifier)
        secureStore.values[MultiServerMigration.LegacyKeys.plexToken] = token
    }

    private func legacyJellyfin(token: String?) {
        defaults.set("jellyfin", forKey: MultiServerMigration.LegacyKeys.provider)
        defaults.set(try? JSONEncoder().encode(connection), forKey: MultiServerMigration.LegacyKeys.jellyfinConnection)
        if let token {
            secureStore.values["strimr.jellyfin.token.jf-server.jf-user"] = token
        }
    }

    private func makeContext() -> Context {
        Context(
            defaults: defaults,
            secureStore: secureStore,
            accounts: AccountStore(userDefaults: defaults, secureStore: secureStore),
            profiles: ProfileStore(userDefaults: defaults),
            settings: SettingsManager(userDefaults: defaults),
            favorites: FavoritesStore(userDefaults: defaults),
        )
    }

    @MainActor
    struct Context {
        let defaults: UserDefaults
        let secureStore: InMemorySecureStore
        let accounts: AccountStore
        let profiles: ProfileStore
        let settings: SettingsManager
        let favorites: FavoritesStore

        func migration(resolving user: PlexCloudUser) -> MultiServerMigration {
            migration { _ in user }
        }

        func migration(_ resolve: @escaping (String) async throws -> PlexCloudUser) -> MultiServerMigration {
            MultiServerMigration(
                defaults: defaults,
                secureStore: secureStore,
                accountStore: accounts,
                profileStore: profiles,
                settingsManager: settings,
                favoritesStore: favorites,
                resolvePlexUser: resolve,
            )
        }
    }
}
