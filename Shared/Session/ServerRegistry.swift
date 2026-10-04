import Foundation
import Observation

/// Servers of the active profile: resolves the profile's links into server sessions, connects them in parallel and
/// tracks a status per server. A failing server never affects the others.
@MainActor
@Observable
final class ServerRegistry {
    enum LinkStatus: Equatable {
        case ready
        /// plex.tv or the Jellyfin server refused the token of the link.
        case needsReauthentication
        case unavailable
    }

    private struct Entry {
        var session: ServerSession
        let link: ProfileLink
        /// Plex user (Home uuid) or Jellyfin user that owns the data of this server.
        let userID: String
        var plexResource: PlexCloudResource?
        var plexContext: PlexAPIContext?
        var jellyfinContext: JellyfinAPIContext?
        var connectionFailures = 0
    }

    private(set) var profile: StrimrProfile?
    private(set) var linkStatuses: [String: LinkStatus] = [:]
    /// Changes on every profile activation, so views drop the state of the previous profile.
    private(set) var generation = 0
    private var entries: [ServerIdentity: Entry] = [:]
    private var order: [ServerIdentity] = []
    private var pendingLinks = 0

    @ObservationIgnored let availability: ServerAvailabilityMonitor
    @ObservationIgnored private let accountStore: AccountStore
    @ObservationIgnored private let profileStore: ProfileStore
    @ObservationIgnored private let favoritesStore: FavoritesStore
    @ObservationIgnored private let trackSelectionCoordinator: TrackSelectionCoordinator
    @ObservationIgnored private let versionSelectionStore: MediaVersionSelectionStore
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var retryTasks: [ServerIdentity: Task<Void, Never>] = [:]
    @ObservationIgnored private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var linksTokens: [String: String] = [:]

    private static let maximumRetryDelay: Duration = .seconds(60)

    init(
        accountStore: AccountStore,
        profileStore: ProfileStore,
        favoritesStore: FavoritesStore,
        trackSelectionCoordinator: TrackSelectionCoordinator,
        versionSelectionStore: MediaVersionSelectionStore,
        availability: ServerAvailabilityMonitor,
    ) {
        self.accountStore = accountStore
        self.profileStore = profileStore
        self.favoritesStore = favoritesStore
        self.trackSelectionCoordinator = trackSelectionCoordinator
        self.versionSelectionStore = versionSelectionStore
        self.availability = availability
        #if os(tvOS)
            availability.onServerBecameReachable = { [weak self] server in
                self?.serverBecameReachable(server)
            }
            availability.onNetworkPathRestored = { [weak self] in
                self?.retryUnavailable()
            }
        #else
            OfflineCoordinator.shared.observeReachability { [weak self] server in
                self?.serverBecameReachable(server)
            }
            OfflineCoordinator.shared.observeNetworkRestored { [weak self] in
                self?.retryUnavailable()
            }
        #endif
    }

    // MARK: - Reading

    /// Sessions in link order, with the reachability reported by the availability monitor.
    var sessions: [ServerSession] {
        order.compactMap { entries[$0]?.session }.map { session in
            var session = session
            if session.status == .ready, availability.isUnreachable(session.identity) {
                session.status = .unreachable
            }
            return session
        }
    }

    var enabledSessions: [ServerSession] {
        sessions.filter(\.isEnabled)
    }

    var activeSessions: [ServerSession] {
        sessions.filter(\.isActive)
    }

    var readyServers: Set<ServerIdentity> {
        Set(activeSessions.map(\.identity))
    }

    /// Enabled servers with services, reachable or not: cached content and downloads still work while unreachable.
    var connectedServices: [MediaServices] {
        order.compactMap { entries[$0] }
            .filter { $0.session.isEnabled && $0.session.status == .ready }
            .compactMap(\.session.services)
    }

    /// Several enabled servers: rows and lists then show which server they come from.
    var hasMultipleServers: Bool {
        order.count(where: { entries[$0]?.session.isEnabled == true }) > 1
    }

    var isConnecting: Bool {
        pendingLinks > 0 || entries.values.contains { $0.session.isEnabled && $0.session.status == .connecting }
    }

    func session(for server: ServerIdentity) -> ServerSession? {
        sessions.first { $0.identity == server }
    }

    /// Services of an enabled server of the active profile; `nil` for servers outside the profile.
    func services(for server: ServerIdentity) -> MediaServices? {
        guard let entry = entries[server], entry.session.isEnabled else { return nil }
        return entry.session.services
    }

    func serverName(for server: ServerIdentity) -> String? {
        entries[server]?.session.name
    }

    func sessions(accountID: String) -> [ServerSession] {
        sessions.filter { $0.accountID == accountID }
    }

    func plexConnectionKind(for server: ServerIdentity) -> PlexConnectionKind? {
        entries[server]?.plexContext?.connectionKind
    }

    func plexResource(for server: ServerIdentity) -> PlexCloudResource? {
        entries[server]?.plexResource
    }

    // MARK: - Activation

    /// Resolves the links of `profile` and starts connecting its enabled servers in parallel.
    func activate(profile: StrimrProfile, links: [ProfileLink]) {
        deactivate()
        self.profile = profile
        generation += 1
        pendingLinks = links.count
        for link in links {
            linkStatuses[link.accountID] = .ready
            let task = Task { [weak self] in
                await self?.resolve(link)
                self?.linkResolved()
            }
            tasks.append(task)
        }
        if links.isEmpty {
            resumeReadyWaiters()
        }
    }

    /// Returns once a server is ready, every connection attempt is over, or `timeout` elapsed.
    func waitForFirstReady(timeout: Duration) async {
        guard readyServers.isEmpty, isConnecting else { return }
        await withCheckedContinuation { continuation in
            readyWaiters.append(continuation)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resumeReadyWaiters()
            }
        }
    }

    func deactivate() {
        for task in tasks {
            task.cancel()
        }
        tasks = []
        for task in retryTasks.values {
            task.cancel()
        }
        retryTasks = [:]
        for server in order {
            availability.untrack(server)
        }
        entries = [:]
        order = []
        linkStatuses = [:]
        linksTokens = [:]
        pendingLinks = 0
        profile = nil
        publishServices()
        resumeReadyWaiters()
    }

    /// Enables or disables a server for the active profile only.
    func setEnabled(_ enabled: Bool, server: ServerIdentity) {
        guard let profile, var entry = entries[server] else { return }
        profileStore.setServer(server.id, enabled: enabled, profileID: profile.id, accountID: entry.link.accountID)
        entry.session.isEnabled = enabled
        if enabled {
            entry.session.status = .connecting
            entries[server] = entry
            connect(server)
        } else {
            retryTasks.removeValue(forKey: server)?.cancel()
            availability.untrack(server)
            entry.session.services = nil
            entry.plexContext = nil
            entry.jellyfinContext = nil
            entry.session.status = .connecting
            entries[server] = entry
            publishServices()
        }
    }

    /// Saves (after checking it with the server) or removes the custom address of a Plex server, then moves the
    /// server to it: a connected server switches in place, any other one reconnects.
    func setCustomAddress(_ url: URL?, server: ServerIdentity) async throws {
        guard let entry = entries[server], let resource = entry.plexResource else {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }
        let liveContext = entry.session.services == nil ? nil : entry.plexContext
        if let url {
            try await (liveContext ?? PlexAPIContext()).selectServer(resource, customURL: url)
        } else {
            PlexAPIContext().removeCustomServerURL(for: resource)
            if let liveContext {
                do {
                    try await liveContext.refreshServerAccess(using: resource)
                } catch {
                    guard !Task.isCancelled, !error.isCancellation else { throw error }
                    connect(server)
                    return
                }
            }
        }
        guard entries[server]?.session.isEnabled == true else { return }
        if liveContext == nil {
            entries[server]?.session.status = .connecting
            connect(server)
        } else {
            availability.refresh()
        }
    }

    /// Reloads the servers of an account after the user signed in again.
    func reload(accountID: String) {
        guard let profile else { return }
        let links = profileStore.links(for: profile).filter { $0.accountID == accountID }
        for server in order where entries[server]?.link.accountID == accountID {
            retryTasks.removeValue(forKey: server)?.cancel()
            availability.untrack(server)
            entries[server] = nil
        }
        order.removeAll { entries[$0] == nil }
        linksTokens[accountID] = nil
        publishServices()
        pendingLinks += links.count
        for link in links {
            linkStatuses[link.accountID] = .ready
            tasks.append(Task { [weak self] in
                await self?.resolve(link)
                self?.linkResolved()
            })
        }
    }

    /// Retries the servers that could not be reached, e.g. when the app returns to the foreground.
    func retryUnavailable() {
        for server in order {
            guard let entry = entries[server], entry.session.isEnabled else { continue }
            if entry.session.services == nil, entry.session.status == .unreachable {
                connect(server)
            }
        }
        availability.refresh()
    }

    /// A request found the token of `server` revoked: only this server is affected.
    func markNeedsReauthentication(_ server: ServerIdentity) {
        guard var entry = entries[server] else { return }
        entry.session.status = .needsReauthentication
        entries[server] = entry
        publishServices()
    }

    func handleTerminalAccessFailure(_ error: MediaServerAccessRecoveryError, server: ServerIdentity) {
        switch error {
        case .accountUnauthorized:
            guard let accountID = entries[server]?.link.accountID else { return }
            linkStatuses[accountID] = .needsReauthentication
            for other in order where entries[other]?.link.accountID == accountID {
                markNeedsReauthentication(other)
            }
        case .serverUnavailable:
            markNeedsReauthentication(server)
        case .connectionFailed:
            availability.reportTransportFailure(on: server)
        }
    }

    // MARK: - Links

    private func linkResolved() {
        pendingLinks = max(0, pendingLinks - 1)
        if pendingLinks == 0, !isConnecting {
            resumeReadyWaiters()
        }
    }

    private func resolve(_ link: ProfileLink) async {
        guard let account = accountStore.account(id: link.accountID) else {
            linkStatuses[link.accountID] = .unavailable
            return
        }
        switch (account, link.user) {
        case let (.plex(plexAccount), .plexHome(uuid)):
            await resolvePlex(link: link, account: plexAccount, userUUID: uuid)
        case let (.jellyfin(jellyfinAccount), .jellyfin):
            resolveJellyfin(link: link, account: jellyfinAccount)
        default:
            linkStatuses[link.accountID] = .unavailable
        }
    }

    private func resolveJellyfin(link: ProfileLink, account: JellyfinAccount) {
        let server = account.server
        guard entries[server] == nil, !Task.isCancelled else { return }
        add(Entry(
            session: ServerSession(
                identity: server,
                name: account.connection.serverName,
                accountID: link.accountID,
                services: nil,
                isEnabled: isEnabled(server, link: link),
                status: .connecting,
            ),
            link: link,
            userID: account.connection.userID,
        ))
        connect(server)
    }

    private func resolvePlex(link: ProfileLink, account: PlexAccount, userUUID: String) async {
        let cached = accountStore.cachedResources(userUUID: userUUID)
        if let cached {
            addPlexServers(cached, link: link, userUUID: userUUID, replacing: false)
        }
        do {
            let token = try await plexToken(link: link, account: account, userUUID: userUUID)
            let resources = try await Self.fetchServers(token: token)
            guard !Task.isCancelled else { return }
            accountStore.setCachedResources(resources, userUUID: userUUID)
            addPlexServers(resources, link: link, userUUID: userUUID, replacing: cached != nil)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            if error.isAuthenticationFailure {
                linkStatuses[link.accountID] = .needsReauthentication
                for server in order where entries[server]?.link == link {
                    markNeedsReauthentication(server)
                }
            } else if cached == nil {
                linkStatuses[link.accountID] = .unavailable
                if !error.isTransportFailure {
                    ErrorReporter.capture(error)
                }
            }
        }
    }

    /// Token of the Plex user of a link: the cached Home token, the account token for the account owner, or a fresh
    /// `/switch` for unprotected Home users.
    private func plexToken(link: ProfileLink, account: PlexAccount, userUUID: String) async throws -> String {
        if let token = linksTokens[link.accountID + userUUID] {
            return token
        }
        if let token = accountStore.homeToken(accountID: link.accountID, userUUID: userUUID) {
            linksTokens[link.accountID + userUUID] = token
            return token
        }
        guard let accountToken = try accountStore.token(forAccountID: link.accountID) else {
            throw PlexServerAccessRecoveryError.accountUnauthorized
        }
        if userUUID == account.id {
            linksTokens[link.accountID + userUUID] = accountToken
            return accountToken
        }
        let context = PlexAPIContext()
        await context.waitForBootstrap()
        context.setAuthToken(accountToken)
        let user = try await UserRepository(context: context).switchUser(uuid: userUUID, pin: nil)
        accountStore.setHomeToken(user.authToken, accountID: link.accountID, userUUID: userUUID)
        linksTokens[link.accountID + userUUID] = user.authToken
        return user.authToken
    }

    /// Token of the profile's watchlist account: its parent account for a Plex Home profile, otherwise the chosen or
    /// first linked Plex account. There is no merge between Plex accounts.
    private func watchlistToken() async -> String? {
        guard let profile,
              let accountID = profileStore.watchlistAccountID(for: profile, accounts: accountStore.accounts),
              let link = profileStore.links(for: profile).first(where: { $0.accountID == accountID }),
              case let .plexHome(userUUID) = link.user,
              case let .plex(account)? = accountStore.account(id: accountID)
        else { return nil }
        return try? await plexToken(link: link, account: account, userUUID: userUUID)
    }

    static func fetchServers(token: String) async throws -> [PlexCloudResource] {
        let context = PlexAPIContext()
        await context.waitForBootstrap()
        context.setAuthToken(token)
        do {
            return try await ResourceRepository(context: context).getAvailableResources().filter(\.isServer)
        } catch let error as PlexAPIError where error.isUnauthorized {
            throw PlexServerAccessRecoveryError.accountUnauthorized
        }
    }

    /// Adds the servers of a Plex link. A server reachable through several links keeps the link of its owner when
    /// that link belongs to the profile, otherwise the first one. With `replacing`, servers no longer returned by
    /// this link are dropped; that only happens after a successful load.
    private func addPlexServers(
        _ resources: [PlexCloudResource],
        link: ProfileLink,
        userUUID: String,
        replacing: Bool,
    ) {
        guard !Task.isCancelled else { return }
        let identities = Set(resources.map { ServerIdentity(provider: .plex, id: $0.clientIdentifier) })
        if replacing {
            for server in order where entries[server]?.link == link && !identities.contains(server) {
                retryTasks.removeValue(forKey: server)?.cancel()
                availability.untrack(server)
                entries[server] = nil
            }
            order.removeAll { entries[$0] == nil }
        }
        for resource in resources {
            let server = ServerIdentity(provider: .plex, id: resource.clientIdentifier)
            if var existing = entries[server] {
                if existing.link == link {
                    existing.plexResource = resource
                    entries[server] = existing
                    refreshPlexAccess(server)
                    continue
                }
                let existingIsOwned = existing.plexResource?.owned == true
                guard resource.owned == true, !existingIsOwned else { continue }
                retryTasks.removeValue(forKey: server)?.cancel()
                availability.untrack(server)
                entries[server] = nil
                order.removeAll { $0 == server }
            }
            add(Entry(
                session: ServerSession(
                    identity: server,
                    name: resource.name,
                    accountID: link.accountID,
                    services: nil,
                    isEnabled: isEnabled(server, link: link),
                    status: .connecting,
                ),
                link: link,
                userID: userUUID,
                plexResource: resource,
            ))
            connect(server)
        }
        publishServices()
    }

    private func isEnabled(_ server: ServerIdentity, link: ProfileLink) -> Bool {
        profileStore.isServerEnabled(server.id, profileID: link.profileID, accountID: link.accountID)
    }

    private func add(_ entry: Entry) {
        entries[entry.session.identity] = entry
        if !order.contains(entry.session.identity) {
            order.append(entry.session.identity)
        }
    }

    // MARK: - Connection

    private func connect(_ server: ServerIdentity) {
        guard let entry = entries[server], entry.session.isEnabled else { return }
        retryTasks.removeValue(forKey: server)?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            switch server.provider {
            case .plex:
                await connectPlex(server)
            case .jellyfin:
                await connectJellyfin(server)
            }
        }
        tasks.append(task)
    }

    private func connectPlex(_ server: ServerIdentity) async {
        guard let entry = entries[server], let resource = entry.plexResource,
              case let .plexHome(userUUID) = entry.link.user,
              case let .plex(account)? = accountStore.account(id: entry.link.accountID)
        else { return }
        let context = PlexAPIContext()
        await context.waitForBootstrap()
        do {
            let token = try await plexToken(link: entry.link, account: account, userUUID: userUUID)
            context.setAuthToken(token)
            context.watchlistAuthToken = await watchlistToken()
            context.configureServerAccessRecovery { [weak self] _ in
                guard let self else { throw PlexServerAccessRecoveryError.connectionFailed }
                try await recoverPlexAccess(server)
            }
            #if os(tvOS)
                try await context.selectServer(resource)
            #else
                // Start from the last connection that worked so the app stays usable offline; it is refreshed below.
                if context.restoreServerAccess(using: resource) {
                    Task { try? await context.refreshServerAccess(using: resource) }
                } else {
                    try await context.selectServer(resource)
                }
            #endif
            guard !Task.isCancelled, entries[server]?.session.isEnabled == true else { return }
            let services = PlexMediaServicesFactory.make(
                context: context,
                serverName: resource.name,
                userID: entry.userID,
                favoritesProfileID: entry.link.profileID,
                favoritesStore: favoritesStore,
                trackSelectionCoordinator: trackSelectionCoordinator,
                versionSelectionStore: versionSelectionStore,
            )
            markReady(server, services: services) { $0.plexContext = context }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            if error.isAuthenticationFailure {
                linkStatuses[entry.link.accountID] = .needsReauthentication
                markNeedsReauthentication(server)
            } else {
                markUnreachable(server)
            }
        }
    }

    private func connectJellyfin(_ server: ServerIdentity) async {
        guard let entry = entries[server],
              case let .jellyfin(account)? = accountStore.account(id: entry.link.accountID)
        else { return }
        let token: String
        do {
            guard let stored = try accountStore.token(forAccountID: entry.link.accountID) else {
                linkStatuses[entry.link.accountID] = .needsReauthentication
                markNeedsReauthentication(server)
                return
            }
            token = stored
        } catch {
            ErrorReporter.capture(error)
            markUnreachable(server)
            return
        }
        let context = JellyfinAPIContext()
        context.configure(connection: account.connection, token: token)
        context.configureAuthenticationRequiredHandler { [weak self] in
            self?.linkStatuses[entry.link.accountID] = .needsReauthentication
            self?.markNeedsReauthentication(server)
        }
        #if os(tvOS)
            do {
                _ = try await context.validateAuthenticatedSession()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                if error.isAuthenticationFailure {
                    markNeedsReauthentication(server)
                } else {
                    if !error.isTransportFailure {
                        ErrorReporter.capture(error)
                    }
                    markUnreachable(server)
                }
                return
            }
        #else
            // Start from local state right away; the token is confirmed in the background so the app stays usable
            // when the server is unreachable.
            Task {
                do {
                    _ = try await context.validateAuthenticatedSession()
                } catch {
                    guard !error.isCancellation, !error.isTransportFailure, !error.isAuthenticationFailure else {
                        return
                    }
                    ErrorReporter.capture(error)
                }
            }
        #endif
        guard !Task.isCancelled, entries[server]?.session.isEnabled == true else { return }
        let services = JellyfinMediaServicesFactory.make(
            context: context,
            capabilities: .jellyfin,
            trackSelectionCoordinator: trackSelectionCoordinator,
            versionSelectionStore: versionSelectionStore,
        )
        markReady(server, services: services) { $0.jellyfinContext = context }
    }

    private func markReady(_ server: ServerIdentity, services: MediaServices?, update: (inout Entry) -> Void) {
        guard var entry = entries[server] else { return }
        guard let services else {
            markUnreachable(server)
            return
        }
        update(&entry)
        entry.session.services = services
        entry.session.status = .ready
        entry.connectionFailures = 0
        entries[server] = entry
        retryTasks.removeValue(forKey: server)?.cancel()
        let probeURL = services.availabilityProbeURL
        availability.track(server, probe: ServerAvailabilityMonitor.probe { probeURL?() })
        publishServices()
        resumeReadyWaiters()
    }

    private func markUnreachable(_ server: ServerIdentity) {
        guard var entry = entries[server] else { return }
        entry.session.status = .unreachable
        entry.connectionFailures += 1
        entries[server] = entry
        scheduleRetry(server, attempt: entry.connectionFailures)
        if !isConnecting {
            resumeReadyWaiters()
        }
    }

    private func scheduleRetry(_ server: ServerIdentity, attempt: Int) {
        retryTasks[server]?.cancel()
        let delay = min(Duration.seconds(2 << min(attempt, 5)), Self.maximumRetryDelay)
        retryTasks[server] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, availability.hasNetworkPath else { return }
            retryTasks[server] = nil
            connect(server)
        }
    }

    private func serverBecameReachable(_ server: ServerIdentity) {
        guard let entry = entries[server], entry.session.isEnabled, entry.session.services == nil else { return }
        connect(server)
    }

    private func refreshPlexAccess(_ server: ServerIdentity) {
        guard let entry = entries[server], let context = entry.plexContext, let resource = entry.plexResource else {
            return
        }
        Task { try? await context.refreshServerAccess(using: resource) }
    }

    private func recoverPlexAccess(_ server: ServerIdentity) async throws {
        guard let entry = entries[server], case let .plexHome(userUUID) = entry.link.user,
              case let .plex(account)? = accountStore.account(id: entry.link.accountID),
              let context = entry.plexContext
        else { throw PlexServerAccessRecoveryError.serverUnavailable }
        let token = try await plexToken(link: entry.link, account: account, userUUID: userUUID)
        let resources: [PlexCloudResource]
        do {
            resources = try await Self.fetchServers(token: token)
        } catch {
            if error.isAuthenticationFailure {
                throw PlexServerAccessRecoveryError.accountUnauthorized
            }
            if Task.isCancelled || error.isCancellation {
                throw error
            }
            throw PlexServerAccessRecoveryError.connectionFailed
        }
        accountStore.setCachedResources(resources, userUUID: userUUID)
        guard let resource = resources.first(where: { $0.clientIdentifier == server.id }) else {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }
        try await context.refreshServerAccess(using: resource)
        entries[server]?.plexResource = resource
    }

    #if os(tvOS)
        /// Ready servers with their address and token, for the Top Shelf extension.
        func topShelfSessions() -> [TopShelfServerCredentials] {
            order.compactMap { server -> TopShelfServerCredentials? in
                guard let entry = entries[server], entry.session.isActive else { return nil }
                if let context = entry.plexContext, let url = context.baseURLServer,
                   let token = context.authTokenServer
                {
                    return TopShelfServerCredentials(
                        session: TopShelfStoredSession(
                            provider: MediaProvider.plex.rawValue,
                            serverURL: url,
                            serverID: server.id,
                            userID: nil,
                        ),
                        token: token,
                    )
                }
                if let connection = entry.jellyfinContext?.connection,
                   let token = try? accountStore.token(forAccountID: entry.link.accountID)
                {
                    return TopShelfServerCredentials(
                        session: TopShelfStoredSession(
                            provider: MediaProvider.jellyfin.rawValue,
                            serverURL: connection.baseURL,
                            serverID: server.id,
                            userID: connection.userID,
                        ),
                        token: token,
                    )
                }
                return nil
            }
        }
    #endif

    // MARK: - Publishing

    private func publishServices() {
        #if !os(tvOS)
            OfflineCoordinator.shared.activate(services: connectedServices)
        #endif
    }

    private func resumeReadyWaiters() {
        let waiters = readyWaiters
        readyWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }
}
