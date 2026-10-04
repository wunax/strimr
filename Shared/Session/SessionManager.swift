import Foundation
import Observation
#if os(tvOS)
    import TVServices
#endif

/// Global session state: accounts, the active profile and its servers. There is no current server: services are
/// always those of an item's server, resolved through `registry`.
@MainActor
@Observable
final class SessionManager {
    enum LoadingPhase {
        case preparing
        case account
        case servers
        case connection
        case libraries

        var title: String {
            switch self {
            case .preparing:
                String(localized: "startup.loading.preparing")
            case .account:
                String(localized: "startup.loading.account")
            case .servers:
                String(localized: "startup.loading.servers")
            case .connection:
                String(localized: "startup.loading.connection")
            case .libraries:
                String(localized: "startup.loading.libraries")
            }
        }
    }

    enum Status: Equatable {
        case hydrating
        /// No account yet: first launch.
        case needsAccount
        case needsProfileSelection
        /// The one-time migration could not finish (Keychain or plex.tv unavailable); it is retried.
        case migrationFailed
        case ready
    }

    struct PlexAccountAddition {
        let account: MediaAccount
        let homeUsers: [PlexHomeUser]
        let ownerUUID: String
        let wasAlreadyAdded: Bool
    }

    let accountStore: AccountStore
    let profileStore: ProfileStore
    let registry: ServerRegistry
    let aggregation: AggregationService
    @ObservationIgnored let trackSelectionCoordinator: TrackSelectionCoordinator
    @ObservationIgnored let versionSelectionStore: MediaVersionSelectionStore
    @ObservationIgnored let favoritesStore: FavoritesStore
    @ObservationIgnored private let settingsManager: SettingsManager

    private(set) var status: Status = .hydrating
    private(set) var loadingPhase: LoadingPhase = .preparing
    private(set) var activeProfile: StrimrProfile?

    @ObservationIgnored private let keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    #if os(tvOS)
        @ObservationIgnored private let topShelfSessionStore = TopShelfSessionStore()
    #endif

    init(
        settingsManager: SettingsManager,
        favoritesStore: FavoritesStore,
        trackSelectionCoordinator: TrackSelectionCoordinator,
        versionSelectionStore: MediaVersionSelectionStore,
        accountStore: AccountStore? = nil,
        profileStore: ProfileStore? = nil,
    ) {
        let accountStore = accountStore ?? AccountStore()
        let profileStore = profileStore ?? ProfileStore()
        self.settingsManager = settingsManager
        self.favoritesStore = favoritesStore
        self.trackSelectionCoordinator = trackSelectionCoordinator
        self.versionSelectionStore = versionSelectionStore
        self.accountStore = accountStore
        self.profileStore = profileStore
        #if os(tvOS)
            let availability = ServerAvailabilityMonitor()
        #else
            let availability = OfflineCoordinator.shared.availability
        #endif
        registry = ServerRegistry(
            accountStore: accountStore,
            profileStore: profileStore,
            favoritesStore: favoritesStore,
            trackSelectionCoordinator: trackSelectionCoordinator,
            versionSelectionStore: versionSelectionStore,
            availability: availability,
        )
        aggregation = AggregationService(reportTransportFailure: { server in
            availability.reportTransportFailure(on: server)
        })
        Task { await hydrate() }
    }

    // MARK: - Profiles

    var accounts: [MediaAccount] {
        accountStore.accounts
    }

    var profiles: [StrimrProfile] {
        profileStore.profiles(accounts: accountStore.accounts)
    }

    /// Avatar of the active profile: the Plex avatar of a Home user; local profiles use their initials.
    var activeProfileAvatarURL: URL? {
        activeProfile?.plexHomeProfile?.user.thumb
    }

    /// Restricted Plex profiles cannot manage accounts nor borrow connections.
    var canManageAccounts: Bool {
        !(activeProfile?.isRestricted ?? false)
    }

    /// plex.tv token of the active profile on its watchlist account, used by plex.tv features such as Seerr sign-in.
    var activePlexToken: String? {
        guard let activeProfile,
              let accountID = profileStore.watchlistAccountID(for: activeProfile, accounts: accounts),
              let link = profileStore.links(for: activeProfile).first(where: { $0.accountID == accountID })
        else { return nil }
        return accountStore.homeToken(accountID: accountID, userUUID: link.user.userID)
            ?? (try? accountStore.token(forAccountID: accountID))
    }

    var activeProfileHasJellyfin: Bool {
        guard let activeProfile else { return false }
        return profileStore.links(for: activeProfile).contains {
            accountStore.account(id: $0.accountID)?.provider == .jellyfin
        }
    }

    func links(for profile: StrimrProfile) -> [ProfileLink] {
        profileStore.links(for: profile)
    }

    func isAccountUnused(_ accountID: String) -> Bool {
        profileStore.profileIDs(using: accountID, accounts: accountStore.accounts).isEmpty
    }

    // MARK: - Startup

    func hydrate() async {
        status = .hydrating
        loadingPhase = .preparing
        let outcome = await makeMigration().run()
        guard outcome != .failed else {
            status = .migrationFailed
            return
        }
        guard !accountStore.accounts.isEmpty else {
            status = .needsAccount
            return
        }
        refreshAllPlexHomeUsers()
        await resumeProfile()
    }

    private func resumeProfile() async {
        let profiles = profiles
        if profileStore.asksProfileOnLaunch, profiles.count > 1 {
            status = .needsProfileSelection
            return
        }
        let candidate = profileStore.activeProfileID.flatMap { id in profiles.first { $0.id == id } }
            ?? (profiles.count == 1 ? profiles.first : nil)
        if let candidate, profileStore.hasLinks(candidate) {
            await activate(candidate)
        } else {
            status = .needsProfileSelection
        }
    }

    private func makeMigration() -> MultiServerMigration {
        MultiServerMigration(
            defaults: .standard,
            secureStore: keychain,
            accountStore: accountStore,
            profileStore: profileStore,
            settingsManager: settingsManager,
            favoritesStore: favoritesStore,
            resolvePlexUser: { token in
                #if !os(tvOS)
                    if let user = OfflineSessionStore().loadPlexUser(token: token), user.uuid != nil {
                        return user
                    }
                #endif
                let context = PlexAPIContext()
                await context.waitForBootstrap()
                context.setAuthToken(token)
                return try await UserRepository(context: context).getUser()
            },
        )
    }

    // MARK: - Profile activation

    /// Activates a profile and shows the app as soon as one server is ready, after three seconds at most; the other
    /// servers join when they connect. A Plex Home token, when given, comes from a fresh `/switch`.
    func activate(_ profile: StrimrProfile, plexHomeToken: String? = nil) async {
        let links = profileStore.links(for: profile)
        guard !links.isEmpty else {
            status = .needsProfileSelection
            return
        }
        if let plexHomeToken, case let .plexHome(homeProfile) = profile {
            accountStore.setHomeToken(plexHomeToken, accountID: homeProfile.accountID, userUUID: homeProfile.user.uuid)
        }
        status = .hydrating
        loadingPhase = .connection
        activeProfile = profile
        profileStore.setActiveProfile(profile.id)
        registry.activate(profile: profile, links: links)
        await registry.waitForFirstReady(timeout: .seconds(3))
        guard activeProfile?.id == profile.id else { return }
        status = .ready
    }

    func requestProfileSelection() {
        status = .needsProfileSelection
    }

    func cancelProfileSelection() {
        guard activeProfile != nil else { return }
        status = .ready
    }

    /// Re-reads the links of the active profile, e.g. after a connection was added or removed.
    func reloadActiveProfile() {
        guard let activeProfile, let refreshed = profileStore.profile(id: activeProfile.id, accounts: accounts) else {
            return
        }
        self.activeProfile = refreshed
        registry.activate(profile: refreshed, links: profileStore.links(for: refreshed))
    }

    func setAsksProfileOnLaunch(_ value: Bool) {
        profileStore.setAsksProfileOnLaunch(value)
    }

    // MARK: - Plex accounts

    /// Stores a plex.tv account from a PIN sign-in. Its Home users join the profile picker; the account is not linked
    /// to any existing profile.
    func addPlexAccount(token: String) async throws -> PlexAccountAddition {
        let context = PlexAPIContext()
        await context.waitForBootstrap()
        context.setAuthToken(token)
        let repository = UserRepository(context: context)
        let user = try await repository.getUser()
        guard let uuid = user.uuid, !uuid.isEmpty else { throw PlexAPIError.invalidURL }
        let account = MediaAccount.plex(PlexAccount(id: uuid, displayName: MultiServerMigration.displayName(of: user)))
        let wasAlreadyAdded = accountStore.account(id: account.id) != nil
        var users: [PlexHomeUser]
        do {
            users = try await repository.getHomeUsers().users
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { throw error }
            ErrorReporter.capture(error)
            users = profileStore.plexHomeUsers(accountID: account.id)
        }
        if !users.contains(where: { $0.uuid == uuid }) {
            users.insert(MultiServerMigration.homeUser(from: user, uuid: uuid), at: 0)
        }
        try accountStore.save(account, token: token)
        accountStore.setHomeToken(token, accountID: account.id, userUUID: uuid)
        let removedProfiles = profileStore.updatePlexHomeUsers(users, accountID: account.id)
        removeSettings(ofProfiles: removedProfiles)
        return PlexAccountAddition(
            account: account,
            homeUsers: users,
            ownerUUID: uuid,
            wasAlreadyAdded: wasAlreadyAdded,
        )
    }

    /// Gets the token of a Home user, asking Plex with the account token. Protected users need their PIN.
    func switchPlexHomeUser(accountID: String, userUUID: String, pin: String?) async throws -> String {
        guard let accountToken = try accountStore.token(forAccountID: accountID) else {
            throw PlexServerAccessRecoveryError.accountUnauthorized
        }
        let context = PlexAPIContext()
        await context.waitForBootstrap()
        context.setAuthToken(accountToken)
        let user = try await UserRepository(context: context).switchUser(uuid: userUUID, pin: pin)
        accountStore.setHomeToken(user.authToken, accountID: accountID, userUUID: userUUID)
        return user.authToken
    }

    /// Servers a Plex user can reach, for the server choice of the first launch.
    func plexServers(accountID: String, userUUID: String) async throws -> [PlexCloudResource] {
        guard let token = try accountStore.homeToken(accountID: accountID, userUUID: userUUID)
            ?? accountStore.token(forAccountID: accountID)
        else { throw PlexServerAccessRecoveryError.accountUnauthorized }
        let resources = try await ServerRegistry.fetchServers(token: token)
        accountStore.setCachedResources(resources, userUUID: userUUID)
        return resources
    }

    func refreshPlexHomeUsers(accountID: String) async {
        guard let token = try? accountStore.token(forAccountID: accountID) else { return }
        let context = PlexAPIContext()
        await context.waitForBootstrap()
        context.setAuthToken(token)
        do {
            let users = try await UserRepository(context: context).getHomeUsers().users
            guard !users.isEmpty else { return }
            let removed = profileStore.updatePlexHomeUsers(users, accountID: accountID)
            removeSettings(ofProfiles: removed)
            if let activeProfile {
                if removed.contains(activeProfile.id) {
                    registry.deactivate()
                    self.activeProfile = nil
                    status = .needsProfileSelection
                } else if let refreshed = profileStore.profile(id: activeProfile.id, accounts: accounts) {
                    self.activeProfile = refreshed
                }
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation, !error.isTransportFailure else { return }
            if !error.isAuthenticationFailure {
                ErrorReporter.capture(error)
            }
        }
    }

    private func refreshAllPlexHomeUsers() {
        for account in accountStore.plexAccounts {
            Task { await refreshPlexHomeUsers(accountID: MediaAccount.plexID(account.id)) }
        }
    }

    // MARK: - Jellyfin accounts

    /// Stores a Jellyfin account. Without a target profile it joins the active profile, or a new local profile named
    /// after the user when there is no profile yet.
    @discardableResult
    func addJellyfinAccount(
        authenticatedSession: JellyfinAuthenticatedSession,
        connection: JellyfinConnection,
        linkingTo profileID: String? = nil,
    ) throws -> MediaAccount {
        let account = MediaAccount.jellyfin(JellyfinAccount(connection: connection))
        do {
            try accountStore.save(account, token: authenticatedSession.accessToken)
        } catch {
            ErrorReporter.capture(error)
            throw error
        }
        let targetProfileID: String = if let profileID {
            profileID
        } else if let activeProfile {
            activeProfile.id
        } else if let existing = profiles.first {
            existing.id
        } else {
            profileStore.createLocalProfile(name: connection.username).id
        }
        profileStore.addLink(ProfileLink(
            profileID: targetProfileID,
            accountID: account.id,
            user: .jellyfin(userID: connection.userID),
        ))
        if activeProfile?.id == targetProfileID {
            registry.reload(accountID: account.id)
        }
        return account
    }

    // MARK: - Links

    func addLink(_ link: ProfileLink) {
        profileStore.addLink(link)
        if activeProfile?.id == link.profileID {
            registry.reload(accountID: link.accountID)
        }
    }

    func removeLink(profileID: String, accountID: String) {
        profileStore.removeLink(profileID: profileID, accountID: accountID)
        if activeProfile?.id == profileID {
            reloadActiveProfile()
        }
    }

    // MARK: - Local profiles

    @discardableResult
    func createLocalProfile(name: String, pin: String?) -> LocalProfile {
        profileStore.createLocalProfile(name: name, pin: pin)
    }

    /// Removes the profile, its links and its settings; accounts stay in the settings.
    func deleteLocalProfile(_ profileID: String) {
        profileStore.deleteLocalProfile(id: profileID)
        removeSettings(ofProfiles: [profileID])
        if activeProfile?.id == profileID {
            registry.deactivate()
            activeProfile = nil
            status = accountStore.accounts.isEmpty ? .needsAccount : .needsProfileSelection
        }
    }

    private func removeSettings(ofProfiles profileIDs: [String]) {
        for profileID in profileIDs {
            settingsManager.removeSettings(profileID: profileID)
            favoritesStore.removeProfile(profileID)
        }
    }

    // MARK: - Accounts

    /// Download owners of an account, to offer deleting its downloads before removing it.
    func owners(ofAccount accountID: String) -> [MediaOwner] {
        servers(ofAccount: accountID).flatMap { server, userIDs in
            userIDs.map { MediaOwner(server: server, userID: $0) }
        }
    }

    /// Removes an account and everything that refers to it: links, server choices and the settings of servers no
    /// other account reaches.
    func removeAccount(_ accountID: String) {
        guard accountStore.account(id: accountID) != nil else { return }
        let servers = Set(servers(ofAccount: accountID).keys)
        let otherServers = Set(accountStore.accounts.filter { $0.id != accountID }
            .flatMap { self.servers(ofAccount: $0.id).keys })
        let homeUsers = profileStore.plexHomeUsers(accountID: accountID)
        let removedHomeProfiles = homeUsers.map { PlexHomeProfile.id(userUUID: $0.uuid) }
        let wasActiveProfileAffected = activeProfile.map { profile in
            removedHomeProfiles.contains(profile.id) || profileStore.links(for: profile)
                .contains { $0.accountID == accountID }
        } ?? false

        profileStore.removeAccount(accountID)
        do {
            try accountStore.remove(accountID: accountID)
        } catch {
            ErrorReporter.capture(error)
        }
        for user in homeUsers {
            accountStore.removeHomeToken(accountID: accountID, userUUID: user.uuid)
            accountStore.removeCachedResources(userUUID: user.uuid)
        }
        settingsManager.removeSettings(of: servers.subtracting(otherServers))
        removeSettings(ofProfiles: removedHomeProfiles)

        guard wasActiveProfileAffected, let activeProfile else { return }
        if removedHomeProfiles.contains(activeProfile.id) {
            registry.deactivate()
            self.activeProfile = nil
            status = accountStore.accounts.isEmpty ? .needsAccount : .needsProfileSelection
        } else if profileStore.hasLinks(activeProfile) {
            reloadActiveProfile()
        } else {
            registry.deactivate()
            self.activeProfile = nil
            status = accountStore.accounts.isEmpty ? .needsAccount : .needsProfileSelection
        }
    }

    /// Servers known for an account and the users that own data on them.
    private func servers(ofAccount accountID: String) -> [ServerIdentity: Set<String>] {
        guard let account = accountStore.account(id: accountID) else { return [:] }
        var result: [ServerIdentity: Set<String>] = [:]
        switch account {
        case let .jellyfin(jellyfin):
            result[jellyfin.server] = [jellyfin.connection.userID]
        case .plex:
            for user in profileStore.plexHomeUsers(accountID: accountID) {
                for resource in accountStore.cachedResources(userUUID: user.uuid) ?? [] {
                    result[ServerIdentity(provider: .plex, id: resource.clientIdentifier), default: []]
                        .insert(user.uuid)
                }
            }
            for link in profileStore.state.links where link.accountID == accountID {
                for resource in accountStore.cachedResources(userUUID: link.user.userID) ?? [] {
                    result[ServerIdentity(provider: .plex, id: resource.clientIdentifier), default: []]
                        .insert(link.user.userID)
                }
            }
        }
        for session in registry.sessions(accountID: accountID) {
            result[session.identity, default: []].formUnion(session.services.map { [$0.owner.userID] } ?? [])
        }
        return result
    }

    // MARK: - First launch

    /// Ends the first-launch flow on the profile chosen during setup.
    func finishFirstLaunch() async {
        await resumeProfile()
    }

    // MARK: - Failures

    func handleTerminalServerAccessFailure(_ error: MediaServerAccessRecoveryError, server: ServerIdentity) {
        registry.handleTerminalAccessFailure(error, server: server)
    }

    #if os(tvOS)
        /// Shares the active profile's servers with the Top Shelf extension.
        func updateTopShelf() {
            let sessions = registry.topShelfSessions()
            do {
                if sessions.isEmpty {
                    topShelfSessionStore.clear()
                } else {
                    try topShelfSessionStore.save(sessions)
                }
            } catch {
                ErrorReporter.capture(error)
            }
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    #endif
}
