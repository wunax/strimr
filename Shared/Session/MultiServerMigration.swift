import Foundation

/// One-time move from the single provider/server session to accounts and profiles. It is versioned and idempotent:
/// nothing is removed before every new value is written, and a failure leaves the old keys for the next launch.
@MainActor
struct MultiServerMigration {
    enum Outcome: Equatable {
        case alreadyMigrated
        case nothingToMigrate
        case migrated(profileID: String)
        case failed
    }

    enum LegacyKeys {
        static let provider = "strimr.activeProvider"
        static let plexServerIdentifier = "strimr.plex.serverIdentifier"
        static let plexToken = "strimr.plex.authToken"
        static let jellyfinConnection = "strimr.jellyfin.connection.v1"
    }

    static let versionKey = "strimr.multiServer.migrationVersion"
    static let currentVersion = 1

    let defaults: UserDefaults
    let secureStore: any SecureStore
    let accountStore: AccountStore
    let profileStore: ProfileStore
    let settingsManager: SettingsManager
    let favoritesStore: FavoritesStore
    /// The Plex user owning a token: the offline snapshot when there is one, plex.tv otherwise.
    let resolvePlexUser: (String) async throws -> PlexCloudUser
    /// The server of the previous session, so it can start offline before plex.tv is reached.
    var legacyPlexResource: () -> PlexCloudResource? = { nil }

    func run() async -> Outcome {
        guard defaults.integer(forKey: Self.versionKey) < Self.currentVersion else { return .alreadyMigrated }
        do {
            let outcome = switch try legacyProvider() {
            case .plex:
                try await migratePlex()
            case .jellyfin:
                try migrateJellyfin()
            case nil:
                Outcome.nothingToMigrate
            }
            removeLegacyKeys()
            defaults.set(Self.currentVersion, forKey: Self.versionKey)
            return outcome
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return .failed }
            if !error.isTransportFailure {
                ErrorReporter.capture(error)
            }
            return .failed
        }
    }

    // MARK: - Providers

    private func legacyProvider() throws -> MediaProvider? {
        if let rawValue = defaults.string(forKey: LegacyKeys.provider),
           let provider = MediaProvider(rawValue: rawValue)
        {
            return provider
        }
        if try secureStore.string(forKey: LegacyKeys.plexToken) != nil {
            return .plex
        }
        if defaults.data(forKey: LegacyKeys.jellyfinConnection) != nil {
            return .jellyfin
        }
        return nil
    }

    private func migratePlex() async throws -> Outcome {
        guard let token = try secureStore.string(forKey: LegacyKeys.plexToken) else { return .nothingToMigrate }
        let user = try await resolvePlexUser(token)
        guard let uuid = user.uuid, !uuid.isEmpty else { throw MigrationError.missingPlexUser }

        let account = PlexAccount(id: uuid, displayName: Self.displayName(of: user))
        let accountID = MediaAccount.plexID(uuid)
        let profileID = PlexHomeProfile.id(userUUID: uuid)
        let serverID = defaults.string(forKey: LegacyKeys.plexServerIdentifier)
        let server = serverID.map { ServerIdentity(provider: .plex, id: $0) }
        let legacyAccountIdentifier = Self.legacyPlexAccountIdentifier(user)

        try accountStore.save(.plex(account), token: token)
        accountStore.setHomeToken(token, accountID: accountID, userUUID: uuid)
        if let resource = legacyPlexResource(), resource.clientIdentifier == serverID,
           accountStore.cachedResources(userUUID: uuid) == nil
        {
            accountStore.setCachedResources([resource], userUUID: uuid)
        }

        var state = profileStore.state
        if state.plexHomeUsers[accountID]?.contains(where: { $0.uuid == uuid }) != true {
            state.plexHomeUsers[accountID, default: []].append(Self.homeUser(from: user, uuid: uuid))
        }
        // The selected server was shared by every Home user, so it is the only one enabled for all of them.
        if let serverID {
            state.defaultServerSelections[accountID] = .only([serverID])
        }
        state.activeProfileID = profileID
        profileStore.replaceState(state)

        migrateSettings(
            profileID: profileID,
            server: server,
            scopeID: server.map { Self.scopeID(server: $0, accountIdentifier: legacyAccountIdentifier) },
        )
        favoritesStore.renameProfile(from: legacyAccountIdentifier, to: profileID)
        return .migrated(profileID: profileID)
    }

    private func migrateJellyfin() throws -> Outcome {
        guard let data = defaults.data(forKey: LegacyKeys.jellyfinConnection),
              let connection = try? JSONDecoder().decode(JellyfinConnection.self, from: data)
        else { return .nothingToMigrate }
        let tokenKey = AccountStore.jellyfinTokenKey(serverID: connection.serverID, userID: connection.userID)
        // Without a token the previous version asked to sign in again; the new one starts with no account.
        guard let token = try secureStore.string(forKey: tokenKey) else { return .nothingToMigrate }

        let account = MediaAccount.jellyfin(JellyfinAccount(connection: connection))
        try accountStore.save(account, token: token)

        var state = profileStore.state
        let profileID: String
        if let existing = state.links.first(where: { $0.accountID == account.id }) {
            profileID = existing.profileID
        } else {
            let profile = LocalProfile(name: connection.username)
            state.localProfiles.append(profile)
            state.links.append(ProfileLink(
                profileID: profile.id,
                accountID: account.id,
                user: .jellyfin(userID: connection.userID),
            ))
            profileID = profile.id
        }
        state.activeProfileID = profileID
        profileStore.replaceState(state)

        migrateSettings(
            profileID: profileID,
            server: connection.serverIdentity,
            scopeID: Self.scopeID(server: connection.serverIdentity, accountIdentifier: connection.userID),
        )
        return .migrated(profileID: profileID)
    }

    // MARK: - Settings

    private func migrateSettings(profileID: String, server: ServerIdentity?, scopeID: String?) {
        settingsManager.updateInterface { interface in
            if let server {
                let hidden = interface.hiddenLibraryIds.map { LibraryIdentity(server: server, libraryID: $0) }
                let navigation = interface.navigationLibraryIds.map { LibraryIdentity(server: server, libraryID: $0) }
                if !hidden.isEmpty || !navigation.isEmpty {
                    var libraries = interface.librariesByProfile[profileID] ?? LibraryPreferences()
                    libraries.hiddenLibraries = hidden
                    libraries.navigationLibraries = navigation
                    interface.librariesByProfile[profileID] = libraries
                }
            }
            if let scopeID, let rows = interface.homeRowsByScope[scopeID] {
                var migrated = HomeRowPreferences()
                migrated.orderedRowIDs = Self.uniqued(rows.orderedRowIDs.map(HomeRow.migratedRowID))
                migrated.hiddenRowIDs = Self.uniqued(rows.hiddenRowIDs.map(HomeRow.migratedRowID))
                interface.homeRowsByProfile[profileID] = migrated
            }
            interface.hiddenLibraryIds = []
            interface.navigationLibraryIds = []
            interface.homeRowsByScope = [:]
            interface.multiServerSearchEnabled = nil
        }
    }

    private func removeLegacyKeys() {
        defaults.removeObject(forKey: LegacyKeys.provider)
        defaults.removeObject(forKey: LegacyKeys.plexServerIdentifier)
        defaults.removeObject(forKey: LegacyKeys.jellyfinConnection)
        try? secureStore.deleteValue(forKey: LegacyKeys.plexToken)
    }

    // MARK: - Helpers

    /// `localFavoritesProfileIdentifier` and the account part of the legacy home row scope.
    static func legacyPlexAccountIdentifier(_ user: PlexCloudUser) -> String {
        user.uuid ?? user.id.map(String.init) ?? user.username ?? user.title ?? "default"
    }

    static func scopeID(server: ServerIdentity, accountIdentifier: String) -> String {
        [server.provider.rawValue, server.id, accountIdentifier].joined(separator: "|")
    }

    static func displayName(of user: PlexCloudUser) -> String {
        [user.friendlyName, user.title, user.username].compactMap { $0?.isEmpty == false ? $0 : nil }.first
            ?? "Plex"
    }

    static func homeUser(from user: PlexCloudUser, uuid: String) -> PlexHomeUser {
        PlexHomeUser(
            id: user.id,
            uuid: uuid,
            title: user.title,
            username: user.username,
            email: nil,
            friendlyName: user.friendlyName,
            thumb: user.thumb.flatMap(URL.init(string:)),
            protected: nil,
            pin: nil,
        )
    }

    private static func uniqued(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    enum MigrationError: Error {
        case missingPlexUser
    }
}
