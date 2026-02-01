import Foundation

final class SeerrSettingsRepository {
    private let client: SeerrNetworkClient

    init(baseURL: URL, session: URLSession = .shared) {
        client = SeerrNetworkClient(baseURL: baseURL, session: session)
    }

    func getPublicSettings() async throws -> SeerrSettings {
        try await client.request(path: "settings/public")
    }
}
