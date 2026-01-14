import Foundation

final class ResourceRepository {
    private let network: PlexCloudNetworkClient
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) {
        self.context = context
        network = PlexCloudNetworkClient(authToken: context.authTokenCloud, clientIdentifier: context.clientIdentifier)
    }

    func getResources() async throws -> [PlexCloudResource] {
        try await network.request(
            path: "/resources",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "includeHttps", value: "1"),
                URLQueryItem(name: "includeRelay", value: "1"),
            ],
        )
    }
}
