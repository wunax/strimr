import Foundation

final class AuthRepository {
    private let network: PlexCloudNetworkClient
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) {
        self.context = context
        network = PlexCloudNetworkClient(authToken: context.authTokenCloud, clientIdentifier: context.clientIdentifier)
    }

    func requestPin() async throws -> PlexCloudPin {
        try await network.request(
            path: "/pins",
            method: "POST",
            queryItems: [URLQueryItem(name: "strong", value: "true")],
        )
    }

    func pollToken(pinId: Int) async throws -> PlexCloudPin {
        try await network.request(path: "/pins/\(pinId)", method: "GET")
    }
}
