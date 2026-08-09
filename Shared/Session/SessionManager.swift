import Foundation
import Observation
#if os(tvOS)
    import TVServices
#endif

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

    enum Status {
        case hydrating
        case needsProviderSelection
        case signedOut
        case needsJellyfinAuthentication
        case needsProfileSelection
        case needsServerSelection
        case ready
    }

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let jellyfinContext: JellyfinAPIContext
    @ObservationIgnored private let libraryStore: LibraryStore
    private(set) var status: Status = .hydrating
    private(set) var loadingPhase: LoadingPhase = .preparing
    private(set) var provider: MediaProvider?
    private(set) var mediaServices: MediaServices?
    private(set) var jellyfinHydrationError: String?
    private(set) var authToken: String?
    private(set) var user: PlexCloudUser?
    private(set) var plexServer: PlexCloudResource?
    private(set) var availableServers: [PlexCloudResource] = []
    @ObservationIgnored private var serverContexts: [String: PlexAPIContext] = [:]

    @ObservationIgnored private let keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    #if os(tvOS)
        @ObservationIgnored private let topShelfSessionStore = TopShelfSessionStore()
    #endif
    @ObservationIgnored private let tokenKey = "strimr.plex.authToken"
    @ObservationIgnored private let serverIdDefaultsKey = "strimr.plex.serverIdentifier"
    @ObservationIgnored private let providerDefaultsKey = "strimr.activeProvider"
    @ObservationIgnored private let jellyfinConnectionDefaultsKey = "strimr.jellyfin.connection.v1"

    init(
        context: PlexAPIContext,
        jellyfinContext: JellyfinAPIContext,
        libraryStore: LibraryStore,
    ) {
        self.context = context
        self.jellyfinContext = jellyfinContext
        self.libraryStore = libraryStore
        context.configureServerAccessRecovery { [weak self] force in
            guard let self else {
                throw PlexServerAccessRecoveryError.connectionFailed
            }
            try await refreshSelectedServerAccess(force: force)
        }
        Task { await hydrate() }
    }

    func hydrate() async {
        status = .hydrating
        loadingPhase = .preparing
        jellyfinHydrationError = nil
        do {
            let selectedProvider = try storedProvider()
            guard let selectedProvider else {
                provider = nil
                status = .needsProviderSelection
                return
            }

            provider = selectedProvider
            switch selectedProvider {
            case .plex:
                try await hydratePlex()
            case .jellyfin:
                await hydrateJellyfin()
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            await clearSession()
            status = provider == .jellyfin ? .needsJellyfinAuthentication : .signedOut
        }
    }

    func selectProvider(_ provider: MediaProvider) async {
        UserDefaults.standard.set(provider.rawValue, forKey: providerDefaultsKey)
        self.provider = provider
        status = .hydrating
        jellyfinHydrationError = nil
        switch provider {
        case .plex:
            do {
                try await hydratePlex()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                await clearSession()
                status = .signedOut
            }
        case .jellyfin:
            await hydrateJellyfin()
        }
    }

    func changeProvider() async {
        await clearSession()
        jellyfinContext.reset()
        provider = nil
        jellyfinHydrationError = nil
        UserDefaults.standard.removeObject(forKey: providerDefaultsKey)
        #if os(tvOS)
            topShelfSessionStore.clear()
            TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
        status = .needsProviderSelection
    }

    func retryJellyfinHydration() async {
        guard provider == .jellyfin else { return }
        status = .hydrating
        jellyfinHydrationError = nil
        await hydrateJellyfin()
    }

    func signIn(with token: String) async throws {
        do {
            provider = .plex
            UserDefaults.standard.set(MediaProvider.plex.rawValue, forKey: providerDefaultsKey)
            try keychain.setString(token, forKey: tokenKey)
            authToken = token
            context.setAuthToken(token)
            try await bootstrapAuthenticatedSession(
                with: token,
                allowProfileSelection: true,
            )
        } catch {
            if Task.isCancelled || error.isCancellation {
                throw error
            }
            await clearSession()
            status = .signedOut
            throw error
        }
    }

    func signOut() async {
        if provider == .jellyfin {
            await signOutJellyfin()
            return
        }

        await clearSession()
        try? keychain.deleteValue(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: serverIdDefaultsKey)
        #if os(tvOS)
            topShelfSessionStore.clear()
            TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
        status = .signedOut
    }

    func completeJellyfinSignIn(
        authenticatedSession: JellyfinAuthenticatedSession,
        connection: JellyfinConnection,
    ) throws {
        do {
            let encodedConnection = try JSONEncoder().encode(connection)
            try keychain.setString(
                authenticatedSession.accessToken,
                forKey: jellyfinTokenKey(connection: connection),
            )
            UserDefaults.standard.set(encodedConnection, forKey: jellyfinConnectionDefaultsKey)
            UserDefaults.standard.set(MediaProvider.jellyfin.rawValue, forKey: providerDefaultsKey)
            provider = .jellyfin
            activateJellyfinServicesIfAvailable()
            jellyfinHydrationError = nil
            status = .ready
        } catch {
            jellyfinContext.reset()
            ErrorReporter.capture(error)
            throw error
        }
    }

    func switchProfile(to user: PlexCloudUser) async throws {
        let snapshot = (token: authToken, user: self.user, server: plexServer, status: status)

        do {
            try keychain.setString(user.authToken, forKey: tokenKey)
            authToken = user.authToken
            self.user = user
            context.setAuthToken(user.authToken)
            try await bootstrapAuthenticatedSession(
                with: user.authToken,
                allowProfileSelection: false,
            )
        } catch {
            if let token = snapshot.token {
                try? keychain.setString(token, forKey: tokenKey)
                authToken = token
                context.setAuthToken(token)
            }
            self.user = snapshot.user
            plexServer = snapshot.server
            status = snapshot.status
            throw error
        }
    }

    func selectServer(_ server: PlexCloudResource) async throws {
        do {
            loadingPhase = .connection
            try await context.selectServer(server)
            plexServer = server
            activatePlexServicesIfAvailable()
            serverContexts[server.clientIdentifier] = nil
            UserDefaults.standard.set(server.clientIdentifier, forKey: serverIdDefaultsKey)
            #if os(tvOS)
                if let serverURL = context.baseURLServer, let serverToken = context.authTokenServer {
                    try? topShelfSessionStore.save(serverURL: serverURL, token: serverToken)
                    TVTopShelfContentProvider.topShelfContentDidChange()
                }
            #endif
            if authToken != nil {
                loadingPhase = .libraries
                do {
                    try await libraryStore.reloadLibraries()
                } catch {
                    if Task.isCancelled || error.isCancellation {
                        throw error
                    }
                }
                status = .ready
            }
        } catch {
            if Task.isCancelled || error.isCancellation {
                context.removeServer()
                throw error
            }

            plexServer = nil
            context.removeServer()
            UserDefaults.standard.removeObject(forKey: serverIdDefaultsKey)
            #if os(tvOS)
                topShelfSessionStore.clear()
                TVTopShelfContentProvider.topShelfContentDidChange()
            #endif
            status = .needsServerSelection
            throw error
        }
    }

    func requestProfileSelection() async {
        status = .needsProfileSelection
        plexServer = nil
        context.removeServer()
        #if os(tvOS)
            topShelfSessionStore.clear()
            TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
    }

    func requestServerSelection() async {
        status = .needsServerSelection
        plexServer = nil
        context.removeServer()
        UserDefaults.standard.removeObject(forKey: serverIdDefaultsKey)
        #if os(tvOS)
            topShelfSessionStore.clear()
            TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
    }

    func refreshSelectedServerAccess(force _: Bool = false) async throws {
        guard let selectedServerID = plexServer?.clientIdentifier ?? context.serverIdentifier else {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }

        let resources: [PlexCloudResource]
        do {
            resources = try await ResourceRepository(context: context).getAvailableResources()
            availableServers = resources
        } catch let error as PlexAPIError where error.isUnauthorized {
            throw PlexServerAccessRecoveryError.accountUnauthorized
        } catch {
            if Task.isCancelled || error.isCancellation {
                throw error
            }
            throw PlexServerAccessRecoveryError.connectionFailed
        }

        guard let refreshedServer = resources.first(where: {
            $0.clientIdentifier == selectedServerID
        }) else {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }

        try await context.refreshServerAccess(using: refreshedServer)
        plexServer = refreshedServer
        UserDefaults.standard.set(refreshedServer.clientIdentifier, forKey: serverIdDefaultsKey)
        #if os(tvOS)
            if let serverURL = context.baseURLServer, let serverToken = context.authTokenServer {
                try? topShelfSessionStore.save(serverURL: serverURL, token: serverToken)
                TVTopShelfContentProvider.topShelfContentDidChange()
            }
        #endif
    }

    func refreshAvailableServers() async throws -> [PlexCloudResource] {
        let resources = try await ResourceRepository(context: context).getAvailableResources()
        availableServers = resources
        return resources
    }

    func serverContext(for serverIdentifier: String) async throws -> PlexAPIContext {
        if serverIdentifier == plexServer?.clientIdentifier {
            return context
        }
        if let cached = serverContexts[serverIdentifier] {
            return cached
        }

        let resources = availableServers.isEmpty ? try await refreshAvailableServers() : availableServers
        guard let server = resources.first(where: { $0.clientIdentifier == serverIdentifier }) else {
            throw PlexAPIError.unreachableServer
        }

        let serverContext = PlexAPIContext()
        await serverContext.waitForBootstrap()
        if let authToken {
            serverContext.setAuthToken(authToken)
        }
        try await serverContext.selectServer(server)
        serverContext.configureServerAccessRecovery { [weak self, weak serverContext] _ in
            guard let self, let serverContext else {
                throw PlexServerAccessRecoveryError.connectionFailed
            }
            let refreshedServers = try await refreshAvailableServers()
            guard let refreshedServer = refreshedServers.first(where: {
                $0.clientIdentifier == serverIdentifier
            }) else {
                throw PlexServerAccessRecoveryError.serverUnavailable
            }
            try await serverContext.refreshServerAccess(using: refreshedServer)
        }
        serverContexts[serverIdentifier] = serverContext
        return serverContext
    }

    func handleTerminalServerAccessFailure(_ error: PlexServerAccessRecoveryError) async {
        switch error {
        case .accountUnauthorized:
            await signOut()
        case .serverUnavailable:
            await requestServerSelection()
        case .connectionFailed:
            break
        }
    }

    private func bootstrapAuthenticatedSession(
        with token: String,
        allowProfileSelection: Bool,
    ) async throws {
        serverContexts = [:]
        let userRepo = UserRepository(context: context)
        let resourcesRepo = ResourceRepository(context: context)

        loadingPhase = .account
        let userResponse = try await userRepo.getUser()
        user = userResponse
        authToken = token

        if allowProfileSelection {
            do {
                let home = try await userRepo.getHomeUsers()
                if home.users.count > 1 {
                    status = .needsProfileSelection
                    context.removeServer()
                    plexServer = nil
                    #if os(tvOS)
                        topShelfSessionStore.clear()
                        TVTopShelfContentProvider.topShelfContentDidChange()
                    #endif
                    return
                }
            } catch {}
        }

        loadingPhase = .servers
        let resources = try await resourcesRepo.getAvailableResources()
        availableServers = resources

        if let persistedServerId = UserDefaults.standard.string(forKey: serverIdDefaultsKey),
           let server = resources.first(where: { $0.clientIdentifier == persistedServerId })
        {
            try await selectAutomatically(server)
        } else if resources.count == 1, let server = resources.first {
            try await selectAutomatically(server)
        } else {
            plexServer = nil
            context.removeServer()
            status = .needsServerSelection
        }
    }

    private func selectAutomatically(_ server: PlexCloudResource) async throws {
        do {
            try await selectServer(server)
        } catch {
            if Task.isCancelled || error.isCancellation {
                throw error
            }
            ErrorReporter.capture(error)
        }
    }

    private func clearSession() async {
        authToken = nil
        user = nil
        plexServer = nil
        availableServers = []
        serverContexts = [:]
        context.reset()
        mediaServices = nil
        libraryStore.configure(service: nil)
    }

    private func storedProvider() throws -> MediaProvider? {
        if let rawValue = UserDefaults.standard.string(forKey: providerDefaultsKey),
           let stored = MediaProvider(rawValue: rawValue)
        {
            return stored
        }

        if try keychain.string(forKey: tokenKey) != nil {
            UserDefaults.standard.set(MediaProvider.plex.rawValue, forKey: providerDefaultsKey)
            return .plex
        }

        if UserDefaults.standard.data(forKey: jellyfinConnectionDefaultsKey) != nil {
            UserDefaults.standard.set(MediaProvider.jellyfin.rawValue, forKey: providerDefaultsKey)
            return .jellyfin
        }

        return nil
    }

    private func hydratePlex() async throws {
        await context.waitForBootstrap()
        let storedToken = try keychain.string(forKey: tokenKey)
        authToken = storedToken
        if let storedToken {
            context.setAuthToken(storedToken)
            try await bootstrapAuthenticatedSession(
                with: storedToken,
                allowProfileSelection: false,
            )
        } else {
            status = .signedOut
        }
    }

    private func hydrateJellyfin() async {
        guard let data = UserDefaults.standard.data(forKey: jellyfinConnectionDefaultsKey),
              let connection = try? JSONDecoder().decode(JellyfinConnection.self, from: data)
        else {
            status = .needsJellyfinAuthentication
            return
        }

        do {
            guard let token = try keychain.string(forKey: jellyfinTokenKey(connection: connection)) else {
                status = .needsJellyfinAuthentication
                return
            }
            jellyfinContext.configure(connection: connection, token: token)
            _ = try await jellyfinContext.validateAuthenticatedSession()
            guard !Task.isCancelled else { return }
            activateJellyfinServicesIfAvailable()
            status = .ready
        } catch let error as JellyfinAPIError where error == .authenticationRequired {
            try? keychain.deleteValue(forKey: jellyfinTokenKey(connection: connection))
            jellyfinContext.reset()
            status = .needsJellyfinAuthentication
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            jellyfinContext.reset()
            jellyfinHydrationError = String(localized: "jellyfin.errors.serverUnreachable")
            status = .needsJellyfinAuthentication
        }
    }

    private func signOutJellyfin() async {
        let connection = jellyfinContext.connection
        do {
            try await jellyfinContext.send(path: ["Sessions", "Logout"], method: "POST")
        } catch {
            if !Task.isCancelled, !error.isCancellation,
               (error as? JellyfinAPIError) != .serverUnreachable
            {
                ErrorReporter.capture(error)
            }
        }
        if let connection {
            do {
                try keychain.deleteValue(forKey: jellyfinTokenKey(connection: connection))
            } catch {
                ErrorReporter.capture(error)
            }
        }
        UserDefaults.standard.removeObject(forKey: jellyfinConnectionDefaultsKey)
        jellyfinContext.reset()
        mediaServices = nil
        libraryStore.configure(service: nil)
        status = .needsJellyfinAuthentication
    }

    private func jellyfinTokenKey(connection: JellyfinConnection) -> String {
        "strimr.jellyfin.token.\(connection.serverID).\(connection.userID)"
    }

    private func activatePlexServicesIfAvailable() {
        guard let services = PlexMediaServicesFactory.make(context: context, sessionManager: self) else { return }
        mediaServices = services
        libraryStore.configure(service: services.library)
    }

    private func activateJellyfinServicesIfAvailable() {
        guard let services = JellyfinMediaServicesFactory.make(
            context: jellyfinContext,
            capabilities: .jellyfinMVP
        ) else { return }
        mediaServices = services
        libraryStore.configure(service: services.library)
    }
}
