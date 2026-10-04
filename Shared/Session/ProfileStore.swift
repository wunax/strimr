import Foundation
import Observation

/// Local profiles, links, per-profile server activation and the last Plex Home users of each Plex account. Plex Home
/// profiles stay virtual: they are rebuilt from the cached Home users, Plex remaining the source of truth.
@MainActor
@Observable
final class ProfileStore {
    struct State: Codable, Equatable {
        var localProfiles: [LocalProfile] = []
        /// Links added by the user. The link of a Plex Home profile to its account is implicit and never stored.
        var links: [ProfileLink] = []
        /// profileID → accountID → servers of the account the profile uses.
        var serverSelections: [String: [String: ServerSelection]] = [:]
        /// accountID → selection used by profiles that never changed theirs.
        var defaultServerSelections: [String: ServerSelection] = [:]
        /// profileID → Plex account whose watchlist the profile shows.
        var watchlistAccounts: [String: String] = [:]
        /// accountID → Home users of the last successful `/home/users` load.
        var plexHomeUsers: [String: [PlexHomeUser]] = [:]
        var activeProfileID: String?
        var asksProfileOnLaunch = false

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            localProfiles = try container.decodeIfPresent([LocalProfile].self, forKey: .localProfiles) ?? []
            links = try container.decodeIfPresent([ProfileLink].self, forKey: .links) ?? []
            serverSelections = try container.decodeIfPresent(
                [String: [String: ServerSelection]].self,
                forKey: .serverSelections,
            ) ?? [:]
            defaultServerSelections = try container.decodeIfPresent(
                [String: ServerSelection].self,
                forKey: .defaultServerSelections,
            ) ?? [:]
            watchlistAccounts = try container.decodeIfPresent([String: String].self, forKey: .watchlistAccounts) ?? [:]
            plexHomeUsers = try container.decodeIfPresent([String: [PlexHomeUser]].self, forKey: .plexHomeUsers) ?? [:]
            activeProfileID = try container.decodeIfPresent(String.self, forKey: .activeProfileID)
            asksProfileOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .asksProfileOnLaunch) ?? false
        }
    }

    struct BorrowableConnection: Hashable, Identifiable {
        let sourceProfile: StrimrProfile
        let accountID: String
        let user: LinkedUser

        var id: String {
            "\(accountID)|\(user.userID)"
        }
    }

    static let storageKey = "strimr.profiles.v1"

    private(set) var state: State

    @ObservationIgnored private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        if let data = userDefaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(State.self, from: data)
        {
            state = stored
        } else {
            state = State()
        }
    }

    var activeProfileID: String? {
        state.activeProfileID
    }

    var asksProfileOnLaunch: Bool {
        state.asksProfileOnLaunch
    }

    // MARK: - Profiles

    /// Local profiles first, then the Plex Home users of each account in account order. A Home user reachable through
    /// two accounts is listed once.
    func profiles(accounts: [MediaAccount]) -> [StrimrProfile] {
        var result = state.localProfiles.map(StrimrProfile.local)
        var seenUsers = Set<String>()
        for account in accounts {
            guard case let .plex(plexAccount) = account else { continue }
            for user in state.plexHomeUsers[account.id] ?? [] where seenUsers.insert(user.uuid).inserted {
                result.append(.plexHome(PlexHomeProfile(accountID: MediaAccount.plexID(plexAccount.id), user: user)))
            }
        }
        return result
    }

    func profile(id: String, accounts: [MediaAccount]) -> StrimrProfile? {
        profiles(accounts: accounts).first { $0.id == id }
    }

    func setActiveProfile(_ profileID: String?) {
        state.activeProfileID = profileID
        persist()
    }

    func setAsksProfileOnLaunch(_ value: Bool) {
        state.asksProfileOnLaunch = value
        persist()
    }

    @discardableResult
    func createLocalProfile(name: String, pin: String? = nil) -> LocalProfile {
        let trimmedPIN = pin?.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = LocalProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            pin: trimmedPIN.flatMap { $0.isEmpty ? nil : LocalProfilePIN(pin: $0) },
        )
        state.localProfiles.append(profile)
        persist()
        return profile
    }

    func updateLocalProfile(_ profile: LocalProfile) {
        guard let index = state.localProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        state.localProfiles[index] = profile
        persist()
    }

    /// Removes the profile, its links and its server choices. Accounts are left untouched.
    func deleteLocalProfile(id: String) {
        state.localProfiles.removeAll { $0.id == id }
        removeProfileData(profileID: id)
        persist()
    }

    /// Replaces the Home users of an account after a successful `/home/users` load and returns the ids of the
    /// profiles that disappeared, whose links and settings were removed. Never call it after a failed load.
    @discardableResult
    func updatePlexHomeUsers(_ users: [PlexHomeUser], accountID: String) -> [String] {
        let previous = Set((state.plexHomeUsers[accountID] ?? []).map(\.uuid))
        let current = Set(users.map(\.uuid))
        let removedProfileIDs = previous.subtracting(current).map(PlexHomeProfile.id(userUUID:))
        state.plexHomeUsers[accountID] = users
        for profileID in removedProfileIDs {
            removeProfileData(profileID: profileID)
        }
        persist()
        return removedProfileIDs.sorted()
    }

    func plexHomeUsers(accountID: String) -> [PlexHomeUser] {
        state.plexHomeUsers[accountID] ?? []
    }

    // MARK: - Links

    func links(for profile: StrimrProfile) -> [ProfileLink] {
        let explicit = state.links.filter { $0.profileID == profile.id }
        guard case let .plexHome(homeProfile) = profile else { return explicit }
        return [homeProfile.implicitLink] + explicit.filter { $0.accountID != homeProfile.accountID }
    }

    func hasLinks(_ profile: StrimrProfile) -> Bool {
        !links(for: profile).isEmpty
    }

    /// Adds a link, replacing any link of the profile to the same account. A new link enables every server of the
    /// account for the profile.
    func addLink(_ link: ProfileLink) {
        state.links.removeAll { $0.profileID == link.profileID && $0.accountID == link.accountID }
        state.links.append(link)
        state.serverSelections[link.profileID, default: [:]][link.accountID] = .all
        persist()
    }

    func removeLink(profileID: String, accountID: String) {
        state.links.removeAll { $0.profileID == profileID && $0.accountID == accountID }
        state.serverSelections[profileID]?[accountID] = nil
        if state.watchlistAccounts[profileID] == accountID {
            state.watchlistAccounts[profileID] = nil
        }
        persist()
    }

    /// Profiles using the account, implicitly or through a link.
    func profileIDs(using accountID: String, accounts: [MediaAccount]) -> Set<String> {
        Set(profiles(accounts: accounts).filter { profile in
            links(for: profile).contains { $0.accountID == accountID }
        }.map(\.id))
    }

    /// Connections another profile could lend to `profile`: one entry per (account, user), without the servers the
    /// profile already reaches. A Plex account already linked to the profile brings the same servers, so it is
    /// excluded as a whole.
    func borrowableConnections(for profile: StrimrProfile, accounts: [MediaAccount]) -> [BorrowableConnection] {
        let ownLinks = links(for: profile)
        let ownAccountIDs = Set(ownLinks.map(\.accountID))
        let ownJellyfinServers = Set(ownLinks.compactMap { link in
            accounts.first { $0.id == link.accountID }?.jellyfinAccount?.connection.serverID
        })
        var seen = Set<String>()
        var result: [BorrowableConnection] = []
        for source in profiles(accounts: accounts) where source.id != profile.id {
            for link in links(for: source) {
                guard let account = accounts.first(where: { $0.id == link.accountID }),
                      !ownAccountIDs.contains(link.accountID)
                else { continue }
                if let jellyfin = account.jellyfinAccount, ownJellyfinServers.contains(jellyfin.connection.serverID) {
                    continue
                }
                let candidate = BorrowableConnection(sourceProfile: source, accountID: link.accountID, user: link.user)
                if seen.insert(candidate.id).inserted {
                    result.append(candidate)
                }
            }
        }
        return result
    }

    // MARK: - Servers

    func serverSelection(profileID: String, accountID: String) -> ServerSelection {
        state.serverSelections[profileID]?[accountID] ?? state.defaultServerSelections[accountID] ?? .all
    }

    func isServerEnabled(_ serverID: String, profileID: String, accountID: String) -> Bool {
        serverSelection(profileID: profileID, accountID: accountID).isEnabled(serverID)
    }

    func setServer(_ serverID: String, enabled: Bool, profileID: String, accountID: String) {
        let selection = serverSelection(profileID: profileID, accountID: accountID).setting(serverID, enabled: enabled)
        state.serverSelections[profileID, default: [:]][accountID] = selection
        persist()
    }

    func setServerSelection(_ selection: ServerSelection, profileID: String, accountID: String) {
        state.serverSelections[profileID, default: [:]][accountID] = selection
        persist()
    }

    /// Selection applied to every profile that has not chosen its own servers for the account yet.
    func setDefaultServerSelection(_ selection: ServerSelection?, accountID: String) {
        state.defaultServerSelections[accountID] = selection
        persist()
    }

    // MARK: - Watchlist

    /// The account whose Plex watchlist the profile shows: the parent account of a Plex Home profile, otherwise the
    /// chosen account or the first linked Plex account.
    func watchlistAccountID(for profile: StrimrProfile, accounts: [MediaAccount]) -> String? {
        let plexAccountIDs = links(for: profile).map(\.accountID).filter { id in
            accounts.first { $0.id == id }?.provider == .plex
        }
        if let chosen = state.watchlistAccounts[profile.id], plexAccountIDs.contains(chosen) {
            return chosen
        }
        if case let .plexHome(homeProfile) = profile {
            return homeProfile.accountID
        }
        return plexAccountIDs.first
    }

    func setWatchlistAccount(_ accountID: String?, profileID: String) {
        state.watchlistAccounts[profileID] = accountID
        persist()
    }

    // MARK: - Accounts

    /// Forgets everything that refers to a removed account, for every profile.
    func removeAccount(_ accountID: String) {
        let homeProfileIDs = (state.plexHomeUsers[accountID] ?? []).map { PlexHomeProfile.id(userUUID: $0.uuid) }
        state.links.removeAll { $0.accountID == accountID }
        for profileID in state.serverSelections.keys {
            state.serverSelections[profileID]?[accountID] = nil
        }
        state.defaultServerSelections[accountID] = nil
        state.watchlistAccounts = state.watchlistAccounts.filter { $0.value != accountID }
        state.plexHomeUsers[accountID] = nil
        for profileID in homeProfileIDs {
            removeProfileData(profileID: profileID)
        }
        if let active = state.activeProfileID, homeProfileIDs.contains(active) {
            state.activeProfileID = nil
        }
        persist()
    }

    private func removeProfileData(profileID: String) {
        state.links.removeAll { $0.profileID == profileID }
        state.serverSelections[profileID] = nil
        state.watchlistAccounts[profileID] = nil
        if state.activeProfileID == profileID {
            state.activeProfileID = nil
        }
    }

    // MARK: - Persistence

    func replaceState(_ state: State) {
        self.state = state
        persist()
    }

    private func persist() {
        do {
            try defaults.set(JSONEncoder().encode(state), forKey: Self.storageKey)
        } catch {
            ErrorReporter.capture(error)
        }
    }
}
