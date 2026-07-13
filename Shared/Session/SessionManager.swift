import Foundation
import Observation
#if os(tvOS)
    import TVServices
#endif

@MainActor
@Observable
final class SessionManager {
    enum Status {
        case hydrating
        case signedOut
        case needsProfileSelection
        case needsServerSelection
        case ready
    }

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let libraryStore: LibraryStore
    private(set) var status: Status = .hydrating
    private(set) var authToken: String?
    private(set) var user: PlexCloudUser?
    private(set) var plexServer: PlexCloudResource?

    @ObservationIgnored private let keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    #if os(tvOS)
        @ObservationIgnored private let topShelfSessionStore = TopShelfSessionStore()
    #endif
    @ObservationIgnored private let tokenKey = "strimr.plex.authToken"
    @ObservationIgnored private let serverIdDefaultsKey = "strimr.plex.serverIdentifier"

    init(context: PlexAPIContext, libraryStore: LibraryStore) {
        self.context = context
        self.libraryStore = libraryStore
        Task { await hydrate() }
    }

    func hydrate() async {
        status = .hydrating
        do {
            await context.waitForBootstrap()

            let storedToken = try keychain.string(forKey: tokenKey)
            authToken = storedToken
            if let storedToken {
                context.setAuthToken(storedToken)
            }

            if let token = storedToken {
                try await bootstrapAuthenticatedSession(
                    with: token,
                    allowProfileSelection: false,
                )
            } else {
                status = .signedOut
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            await clearSession()
            status = .signedOut
        }
    }

    func signIn(with token: String) async throws {
        do {
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
        await clearSession()
        try? keychain.deleteValue(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: serverIdDefaultsKey)
        #if os(tvOS)
            topShelfSessionStore.clear()
            TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
        status = .signedOut
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
            try await context.selectServer(server)
            plexServer = server
            UserDefaults.standard.set(server.clientIdentifier, forKey: serverIdDefaultsKey)
            #if os(tvOS)
                if let serverURL = context.baseURLServer, let serverToken = context.authTokenServer {
                    try? topShelfSessionStore.save(serverURL: serverURL, token: serverToken)
                    TVTopShelfContentProvider.topShelfContentDidChange()
                }
            #endif
            if authToken != nil {
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

    private func bootstrapAuthenticatedSession(
        with token: String,
        allowProfileSelection: Bool,
    ) async throws {
        let userRepo = UserRepository(context: context)
        let resourcesRepo = ResourceRepository(context: context)

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

        let resources = try await resourcesRepo.getAvailableResources()

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
        context.reset()
    }
}
