import Combine
import Foundation
import SwiftUI

@MainActor
final class SessionCoordinator: ObservableObject {
    enum Status {
        case hydrating
        case signedOut
        case needsServerSelection
        case ready
    }

    @Published private(set) var status: Status = .hydrating
    @Published private(set) var authToken: String?
    @Published private(set) var user: PlexCloudUser?
    @Published private(set) var plexServer: PlexCloudResource?
    @Published private(set) var cloudAPI: PlexCloudAPI?
    @Published private(set) var mediaServerAPI: PlexMediaServerAPI?
    @Published private(set) var clientIdentifier: String = ""

    private let keychain = Keychain(service: "dev.strimr.app")
    private let tokenKey = "strimr.plex.authToken"
    private let clientIdKey = "strimr.plex.clientId"
    private let serverIdDefaultsKey = "strimr.plex.serverIdentifier"

    init() {
        Task { await hydrate() }
    }

    func hydrate() async {
        status = .hydrating
        do {
            clientIdentifier = try await ensureClientIdentifier()
            let storedToken = try keychain.string(forKey: tokenKey)
            authToken = storedToken
            cloudAPI = PlexCloudAPI(clientIdentifier: clientIdentifier, authToken: storedToken)

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
            cloudAPI = PlexCloudAPI(clientIdentifier: clientIdentifier, authToken: token)
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
        mediaServerAPI = PlexMediaServerAPI(resource: server, language: currentLanguageCode())
        if authToken != nil {
            status = .ready
        }
    }

    private func bootstrapAuthenticatedSession(with token: String) async throws {
        guard let cloudAPI else { throw PlexAPIError.invalidURL }

        let userResponse = try await cloudAPI.getUser()
        let resources = try await cloudAPI.getResources().filter { !$0.connections.isEmpty }

        user = userResponse
        authToken = token
        
        if let persistedServerId = UserDefaults.standard.string(forKey: serverIdDefaultsKey),
           let server = resources.first(where: { $0.clientIdentifier == persistedServerId }) {
            selectServer(server)
        } else if resources.count == 1, let server = resources.first {
            selectServer(server)
        } else {
            plexServer = nil
            mediaServerAPI = nil
            status = .needsServerSelection
        }
    }

    private func clearSession() async {
        authToken = nil
        user = nil
        plexServer = nil
        mediaServerAPI = nil
        cloudAPI = PlexCloudAPI(clientIdentifier: clientIdentifier, authToken: nil)
    }

    private func ensureClientIdentifier() async throws -> String {
        if let stored = try keychain.string(forKey: clientIdKey) {
            return stored
        }
        let identifier = UUID().uuidString
        try keychain.setString(identifier, forKey: clientIdKey)
        return identifier
    }

    private func currentLanguageCode() -> String {
        Locale.preferredLanguages.first?
            .split(separator: "-")
            .first
            .map(String.init) ?? "en"
    }
}
