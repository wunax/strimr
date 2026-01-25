import Foundation

final class HubRepository {
    private let network: PlexServerNetworkClient
    private weak var context: PlexAPIContext?

    struct HubParams: QueryItemConvertible {
        var sectionIds: [Int]?
        var count: Int?
        var excludeFields: [String]?
        var excludeContinueWatching: Bool?

        var queryItems: [URLQueryItem] {
            [
                URLQueryItem.makeArray("contentDirectoryID", sectionIds),
                URLQueryItem.make("count", count),
                URLQueryItem.makeArray("excludeFields", excludeFields),
                URLQueryItem.makeBoolFlag("excludeContinueWatching", excludeContinueWatching),
            ].compactMap(\.self)
        }
    }

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }

        self.context = context
        network = PlexServerNetworkClient(authToken: authToken, baseURL: baseURLServer)
    }

    func getContinueWatchingHub(params: HubParams? = nil) async throws -> PlexHubMediaContainer {
        let resolved = params ?? HubParams()
        return try await network.request(path: "/hubs/continueWatching", queryItems: resolved.queryItems)
    }

    func getPromotedHub(
        params: HubParams? = nil,
        includeLibraryPlaylists: Bool? = nil,
    ) async throws -> PlexHubMediaContainer {
        let resolved = params ?? HubParams()
        var queryItems = resolved.queryItems
        if resolved.count == nil {
            queryItems.append(URLQueryItem(name: "count", value: "20"))
        }
        #if !os(tvOS)
            if resolved.excludeFields == nil {
                queryItems.append(URLQueryItem(name: "excludeFields", value: "summary"))
            }
        #endif
        if resolved.excludeContinueWatching == nil {
            queryItems.append(URLQueryItem(name: "excludeContinueWatching", value: "1"))
        }
        let includePlaylists = includeLibraryPlaylists ?? false
        queryItems.append(URLQueryItem(name: "includeLibraryPlaylists", value: includePlaylists ? "1" : "0"))
        return try await network.request(path: "/hubs/promoted", queryItems: queryItems)
    }

    func getSectionHubs(sectionId: Int) async throws -> PlexHubMediaContainer {
        var queryItems = [
            URLQueryItem(name: "count", value: "20"),
        ]
        #if !os(tvOS)
            queryItems.append(URLQueryItem(name: "excludeFields", value: "summary"))
        #endif
        return try await network.request(path: "/hubs/sections/\(sectionId)", queryItems: queryItems)
    }

    func getRelatedMediaHubs(ratingKey: String) async throws -> PlexHubMediaContainer {
        try await network.request(path: "/library/metadata/\(ratingKey)/related")
    }
}
