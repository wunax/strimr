import Foundation

final class PlaylistRepository {
    private let network: PlexServerNetworkClient
    private let serverIdentifier: String

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

        guard let serverIdentifier = context.serverIdentifier else {
            throw PlexAPIError.missingConnection
        }

        self.serverIdentifier = serverIdentifier
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

    func getAllPlaylists(sectionId: Int) async throws -> [PlexItem] {
        try await allPages { pagination in
            try await getPlaylists(sectionId: sectionId, pagination: pagination)
        }
    }

    /// Every playlist of the user, across libraries.
    func getAllPlaylists(playlistType: String, smart: Bool?) async throws -> [PlexItem] {
        try await allPages { pagination in
            try await network.request(
                path: "/playlists",
                queryItems: [
                    URLQueryItem(name: "playlistType", value: playlistType),
                    smart.map { URLQueryItem(name: "smart", value: $0 ? "1" : "0") },
                ].compactMap(\.self),
                headers: pagination.headers,
            )
        }
    }

    func getAllPlaylistItems(ratingKey: String) async throws -> [PlexItem] {
        try await allPages { pagination in
            try await getPlaylistItems(ratingKey: ratingKey, pagination: pagination)
        }
    }

    func createPlaylist(title: String, itemRatingKey: String) async throws {
        try await network.send(
            path: "/playlists",
            queryItems: [
                URLQueryItem(name: "type", value: "video"),
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "smart", value: "0"),
                URLQueryItem(name: "uri", value: metadataURI(for: itemRatingKey)),
            ],
            method: "POST",
        )
    }

    /// Plex skips an item the playlist already holds.
    func addItem(ratingKey: String, toPlaylist playlistRatingKey: String) async throws {
        try await network.send(
            path: "/playlists/\(playlistRatingKey)/items",
            queryItems: [URLQueryItem(name: "uri", value: metadataURI(for: ratingKey))],
            method: "PUT",
        )
    }

    func removeItem(playlistItemID: String, fromPlaylist playlistRatingKey: String) async throws {
        try await network.send(
            path: "/playlists/\(playlistRatingKey)/items/\(playlistItemID)",
            method: "DELETE",
        )
    }

    /// - Parameter afterPlaylistItemID: entry to place it after, nil to make it the first one.
    func moveItem(
        playlistItemID: String,
        after afterPlaylistItemID: String?,
        inPlaylist playlistRatingKey: String,
    ) async throws {
        try await network.send(
            path: "/playlists/\(playlistRatingKey)/items/\(playlistItemID)/move",
            queryItems: [URLQueryItem(name: "after", value: afterPlaylistItemID ?? "0")],
            method: "PUT",
        )
    }

    func renamePlaylist(ratingKey: String, title: String) async throws {
        try await network.send(
            path: "/playlists/\(ratingKey)",
            queryItems: [URLQueryItem(name: "title", value: title)],
            method: "PUT",
        )
    }

    func deletePlaylist(ratingKey: String) async throws {
        try await network.send(path: "/playlists/\(ratingKey)", method: "DELETE")
    }

    private func metadataURI(for ratingKey: String) -> String {
        "server://\(serverIdentifier)/com.plexapp.plugins.library/library/metadata/\(ratingKey)"
    }

    private func allPages(
        _ fetch: (PlexPagination) async throws -> PlexItemMediaContainer,
    ) async throws -> [PlexItem] {
        var items: [PlexItem] = []
        while true {
            let container = try await fetch(PlexPagination(start: items.count, size: 200)).mediaContainer
            let page = container.metadata ?? []
            items.append(contentsOf: page)
            guard !page.isEmpty, items.count < container.totalSize ?? 0 else { return items }
        }
    }
}
