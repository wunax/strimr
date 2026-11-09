import Foundation

final class PlayQueueRepository {
    private let network: PlexServerNetworkClient
    private let serverIdentifier: String

    init(context: PlexAPIContext) throws {
        guard context.baseURLServer != nil else {
            throw PlexAPIError.missingConnection
        }

        guard context.authTokenServer != nil else {
            throw PlexAPIError.missingAuthToken
        }

        guard let serverIdentifier = context.serverIdentifier else {
            throw PlexAPIError.missingConnection
        }

        self.serverIdentifier = serverIdentifier
        network = PlexServerNetworkClient(context: context)
    }

    func createQueue(
        for ratingKey: String,
        itemType: PlexItemType,
        type: String = "video",
        shuffle: Bool = false,
        repeatMode: Int = 0,
        continuous: Bool = false,
        startingRatingKey: String? = nil,
    ) async throws -> PlexPlayQueueResponse {
        let uri = metadataURI(for: ratingKey, itemType: itemType)
        var queryItems = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "uri", value: uri),
            URLQueryItem(name: "own", value: "1"),
            URLQueryItem(name: "shuffle", value: shuffle ? "1" : "0"),
            URLQueryItem(name: "repeat", value: String(repeatMode)),
            URLQueryItem(name: "continuous", value: continuous ? "1" : "0"),
        ]
        if let startingRatingKey {
            queryItems.append(URLQueryItem(name: "key", value: "/library/metadata/\(startingRatingKey)"))
        }
        return try await network.request(path: "/playQueues", queryItems: queryItems, method: "POST")
    }

    /// The playlist in its order, starting at the first occurrence of `startingRatingKey`.
    func createPlaylistQueue(
        playlistRatingKey: String,
        startingRatingKey: String,
    ) async throws -> PlexPlayQueueResponse {
        try await network.request(
            path: "/playQueues",
            queryItems: [
                URLQueryItem(name: "type", value: "video"),
                URLQueryItem(name: "uri", value: metadataURI(for: playlistRatingKey, itemType: .playlist)),
                URLQueryItem(name: "key", value: "/library/metadata/\(startingRatingKey)"),
                URLQueryItem(name: "own", value: "1"),
                URLQueryItem(name: "shuffle", value: "0"),
            ],
            method: "POST",
        )
    }

    func getQueue(id: Int) async throws -> PlexPlayQueueResponse {
        try await network.request(path: "/playQueues/\(id)")
    }

    private func metadataURI(for ratingKey: String, itemType: PlexItemType) -> String {
        switch itemType {
        case .collection:
            "server://\(serverIdentifier)/com.plexapp.plugins.library/library/collections/\(ratingKey)"
        case .playlist:
            "server://\(serverIdentifier)/com.plexapp.plugins.library/playlists/\(ratingKey)"
        default:
            "server://\(serverIdentifier)/com.plexapp.plugins.library/library/metadata/\(ratingKey)"
        }
    }
}
