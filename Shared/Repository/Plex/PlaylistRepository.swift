import Foundation

final class PlaylistRepository {
    private let network: PlexServerNetworkClient

    struct PlaylistParams: QueryItemConvertible {
        var sectionId: Int
        var playlistType: String
        var includeCollections: Bool?

        var queryItems: [URLQueryItem] {
            [
                URLQueryItem(name: "type", value: "15"),
                URLQueryItem.make("sectionID", sectionId),
                URLQueryItem.make("playlistType", playlistType),
                URLQueryItem.makeBoolFlag("includeCollections", includeCollections),
            ].compactMap(\.self)
        }
    }

    init(context: PlexAPIContext) throws {
        guard context.baseURLServer != nil else {
            throw PlexAPIError.missingConnection
        }

        guard context.authTokenServer != nil else {
            throw PlexAPIError.missingAuthToken
        }

        network = PlexServerNetworkClient(context: context)
    }

    func getPlaylists(
        sectionId: Int,
        playlistType: String = "video",
        includeCollections: Bool = true,
        pagination: PlexPagination? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolvedPagination = pagination ?? PlexPagination()
        let queryItems = PlaylistParams(
            sectionId: sectionId,
            playlistType: playlistType,
            includeCollections: includeCollections,
        ).queryItems

        return try await network.request(
            path: "/playlists",
            queryItems: queryItems,
            headers: resolvedPagination.headers,
        )
    }

    func getPlaylist(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/playlists/\(ratingKey)")
    }

    func getPlaylistItems(
        ratingKey: String,
        pagination: PlexPagination? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolvedPagination = pagination ?? PlexPagination()
        return try await network.request(
            path: "/playlists/\(ratingKey)/items",
            headers: resolvedPagination.headers,
        )
    }
}
