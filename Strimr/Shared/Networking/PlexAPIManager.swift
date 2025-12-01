import SwiftUI

@Observable
final class PlexAPIManager {
    let cloud: PlexCloudAPI
    private(set) var server: PlexMediaServerAPI?
    private(set) var clientIdentifier: String = ""

    @ObservationIgnored private let keychain = Keychain(service: "dev.strimr.app")
    @ObservationIgnored private let clientIdKey = "strimr.plex.clientId"

    init() {
        cloud = PlexCloudAPI()

        Task {
            await bootstrap()
        }
    }

    private func bootstrap() async {
        do {
            let cid = try await ensureClientIdentifier()
            clientIdentifier = cid
            cloud.setClientIdentifier(cid)
        } catch {
            let fallback = UUID().uuidString
            clientIdentifier = fallback
            cloud.setClientIdentifier(fallback)
        }
    }

    private func ensureClientIdentifier() async throws -> String {
        if let stored = try keychain.string(forKey: clientIdKey) {
            return stored
        }
        let identifier = UUID().uuidString
        try keychain.setString(identifier, forKey: clientIdKey)
        return identifier
    }

    func selectServer(_ resource: PlexCloudResource) {
        server = PlexMediaServerAPI(resource: resource, language: "en")
    }

    func removeServer() {
        server = nil
    }

    func reset() {
        server = nil
        cloud.setAuthToken(nil)
    }
}
