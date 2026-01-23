import Foundation

final class PlayQueueRepository {
    private let network: PlexServerNetworkClient
    private let serverIdentifier: String

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }

        guard let serverIdentifier = context.serverIdentifier else {
            throw PlexAPIError.missingConnection
        }

        self.serverIdentifier = serverIdentifier
        network = PlexServerNetworkClient(
            authToken: authToken,
            baseURL: baseURLServer,
            clientIdentifier: context.clientIdentifier,
        )
    }

    func createQueue(
        for ratingKey: String,
        type: String = "video",
        shuffle: Bool = false,
        repeatMode: Int = 0,
        continuous: Bool = false,
    ) async throws -> PlexPlayQueueResponse {
        try await network.request(
            path: "/playQueues",
            queryItems: [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "uri", value: metadataURI(for: ratingKey)),
                URLQueryItem(name: "own", value: "1"),
                URLQueryItem(name: "shuffle", value: shuffle ? "1" : "0"),
                URLQueryItem(name: "repeat", value: String(repeatMode)),
                URLQueryItem(name: "continuous", value: continuous ? "1" : "0"),
            ],
            method: "POST",
        )
    }

    func getQueue(id: Int) async throws -> PlexPlayQueueResponse {
        try await network.request(path: "/playQueues/\(id)")
    }

    private func metadataURI(for ratingKey: String) -> String {
        "server://\(serverIdentifier)/com.plexapp.plugins.library/library/metadata/\(ratingKey)"
    }
}
