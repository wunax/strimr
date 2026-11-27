import Foundation

final class DiscoverWatchlistRepository {
    private let network: PlexCloudNetworkClient

    init(context: PlexAPIContext) throws {
        guard let authToken = context.watchlistAuthToken ?? context.authTokenCloud else {
            throw PlexAPIError.missingAuthToken
        }

        network = PlexCloudNetworkClient(
            authToken: authToken,
            clientIdentifier: context.clientIdentifier,
            useDiscoverBaseURL: true,
            session: context.session,
        )
    }

    func addToWatchlist(ratingKey: String) async throws {
        try await network.send(
            path: "/actions/addToWatchlist",
            method: "PUT",
            queryItems: [URLQueryItem(name: "ratingKey", value: ratingKey)],
        )
    }

    func removeFromWatchlist(ratingKey: String) async throws {
        try await network.send(
            path: "/actions/removeFromWatchlist",
            method: "PUT",
            queryItems: [URLQueryItem(name: "ratingKey", value: ratingKey)],
        )
    }

    /// Discover rejects larger pages.
    nonisolated static let watchlistPageSize = 25

    func getWatchlist(start: Int, size: Int = watchlistPageSize) async throws -> PlexDiscoverContainer {
        try await container(path: "/library/sections/watchlist/all", queryItems: [
            URLQueryItem(name: "X-Plex-Container-Start", value: String(start)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(size)),
            URLQueryItem(name: "includeGuids", value: "1"),
            URLQueryItem(name: "includeMeta", value: "1"),
        ])
    }

    /// The home section only lists its hubs: each one is then loaded from its own key.
    func getHomeHubs() async throws -> [PlexDiscoverHub] {
        try await container(path: "/hubs/sections/home", queryItems: [
            URLQueryItem(name: "includeMeta", value: "1"),
        ]).hubs
    }

    /// Hub keys can carry their own query, which is kept.
    func getHub(key: String, limit: Int) async throws -> PlexDiscoverContainer {
        let components = URLComponents(string: key)
        return try await container(path: components?.path ?? key, queryItems: (components?.queryItems ?? []) + [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "includeGuids", value: "1"),
            URLQueryItem(name: "includeMeta", value: "1"),
            URLQueryItem(name: "excludeElements", value: "Media,Image"),
        ])
    }

    func getMetadata(ratingKey: String) async throws -> PlexDiscoverMetadata? {
        try await container(path: "/library/metadata/\(ratingKey)", queryItems: [
            URLQueryItem(name: "includeGuids", value: "1"),
        ]).metadata.first
    }

    func getRelated(ratingKey: String) async throws -> [PlexDiscoverMetadata] {
        let container = try await container(path: "/library/metadata/\(ratingKey)/related", queryItems: nil)
        return container.hubs.isEmpty ? container.metadata : container.hubs.flatMap(\.metadata)
    }

    func search(query: String) async throws -> [PlexDiscoverMetadata] {
        try await container(path: "/library/search", queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "searchTypes", value: "movies,tv"),
            URLQueryItem(name: "searchProviders", value: "discover"),
            URLQueryItem(name: "includeGuids", value: "1"),
            URLQueryItem(name: "includeMetadata", value: "1"),
        ]).searchResults.flatMap(\.results).compactMap(\.metadata)
    }

    /// Discover only answers a guid lookup paired with the numeric type, 1 for movies and 2 for shows.
    func match(guid: String, type: Int) async throws -> PlexDiscoverMetadata? {
        try await container(path: "/library/metadata/matches", queryItems: [
            URLQueryItem(name: "type", value: String(type)),
            URLQueryItem(name: "guid", value: guid),
            URLQueryItem(name: "includeGuids", value: "1"),
        ]).metadata.first
    }

    private func container(path: String, queryItems: [URLQueryItem]?) async throws -> PlexDiscoverContainer {
        let response: PlexDiscoverContainerResponse = try await network.request(path: path, queryItems: queryItems)
        return response.mediaContainer
    }
}
