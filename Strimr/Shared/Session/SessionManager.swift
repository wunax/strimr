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

    private let plexApi: PlexAPIManager
    
    private(set) var status: Status = .hydrating
    private(set) var authToken: String?
    private(set) var user: PlexCloudUser?
    private(set) var plexServer: PlexCloudResource?
    private(set) var clientIdentifier: String = ""

    @ObservationIgnored private let keychain = Keychain(service: "dev.strimr.app")
    @ObservationIgnored private let tokenKey = "strimr.plex.authToken"
    @ObservationIgnored private let clientIdKey = "strimr.plex.clientId"
    @ObservationIgnored private let serverIdDefaultsKey = "strimr.plex.serverIdentifier"

    init(apiManager: PlexAPIManager) {
        self.plexApi = apiManager
        Task { await hydrate() }
    }

    func hydrate() async {
        status = .hydrating
        do {
            let storedToken = try keychain.string(forKey: tokenKey)
            authToken = storedToken
            plexApi.cloud.setAuthToken(storedToken)
            
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
            plexApi.cloud.setAuthToken(token)
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

    func selectServer(_ server: PlexCloudResource) {
        plexServer = server
        UserDefaults.standard.set(server.clientIdentifier, forKey: serverIdDefaultsKey)
        plexApi.selectServer(server)
        if authToken != nil {
            status = .ready
        }
    }

    private func bootstrapAuthenticatedSession(with token: String) async throws {
        let userResponse = try await plexApi.cloud.getUser()
        let resources = try await plexApi.cloud.getResources().filter { !$0.connections.isEmpty }

        user = userResponse
        authToken = token
                
        if let persistedServerId = UserDefaults.standard.string(forKey: serverIdDefaultsKey),
           let server = resources.first(where: { $0.clientIdentifier == persistedServerId }) {
            selectServer(server)
        } else if resources.count == 1, let server = resources.first {
            selectServer(server)
        } else {
            plexServer = nil
            plexApi.removeServer()
            status = .needsServerSelection
        }
    }

    private func clearSession() async {
        authToken = nil
        user = nil
        plexServer = nil
        plexApi.reset()
    }
}
