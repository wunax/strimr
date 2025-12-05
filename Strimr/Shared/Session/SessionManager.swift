import Foundation
import Observation

@MainActor
@Observable
final class SessionManager {
    enum Status {
        case hydrating
        case signedOut
        case needsServerSelection
        case ready
    }

    @ObservationIgnored private let context: PlexAPIContext
    private(set) var status: Status = .hydrating
    private(set) var authToken: String?
    private(set) var user: PlexCloudUser?
    private(set) var plexServer: PlexCloudResource?

    @ObservationIgnored private let keychain = Keychain(service: "dev.strimr.app")
    @ObservationIgnored private let tokenKey = "strimr.plex.authToken"
    @ObservationIgnored private let serverIdDefaultsKey = "strimr.plex.serverIdentifier"

    init(context: PlexAPIContext) {
        self.context = context
        Task { await hydrate() }
    }

    func hydrate() async {
        status = .hydrating
        do {
            let storedToken = try keychain.string(forKey: tokenKey)
            authToken = storedToken
            if let storedToken {
                context.setAuthToken(storedToken)
            }

            if let token = storedToken {
                try await bootstrapAuthenticatedSession(with: token)
            } else {
                status = .signedOut
            }
        } catch {
            await clearSession()
            status = .signedOut
        }
    }

    func signIn(with token: String) async {
        do {
            try keychain.setString(token, forKey: tokenKey)
            authToken = token
            context.setAuthToken(token)
            try await bootstrapAuthenticatedSession(with: token)
        } catch {
            await clearSession()
            status = .signedOut
        }
    }

    func signOut() async {
        await clearSession()
        try? keychain.deleteValue(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: serverIdDefaultsKey)
        status = .signedOut
    }

    func selectServer(_ server: PlexCloudResource) async {
        do {
            try await context.selectServer(server)
            plexServer = server
            UserDefaults.standard.set(server.clientIdentifier, forKey: serverIdDefaultsKey)
            if authToken != nil {
                status = .ready
            }
        } catch {
            plexServer = nil
            context.removeServer()
            UserDefaults.standard.removeObject(forKey: serverIdDefaultsKey)
            status = .needsServerSelection
        }
    }

    private func bootstrapAuthenticatedSession(with token: String) async throws {
        let userRepo = UserRepository(context: context)
        let resourcesRepo = ResourceRepository(context: context)

        let userResponse = try await userRepo.getUser()
        let resources = try await resourcesRepo.getResources().filter { !$0.connections.isEmpty }

        user = userResponse
        authToken = token

        if let persistedServerId = UserDefaults.standard.string(forKey: serverIdDefaultsKey),
           let server = resources.first(where: { $0.clientIdentifier == persistedServerId })
        {
            await selectServer(server)
        } else if resources.count == 1, let server = resources.first {
            await selectServer(server)
        } else {
            plexServer = nil
            context.removeServer()
            status = .needsServerSelection
        }
    }

    private func clearSession() async {
        authToken = nil
        user = nil
        plexServer = nil
        context.reset()
    }
}
