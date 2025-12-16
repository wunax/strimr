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
                URLQueryItem.makeArray("sectionIds", sectionIds),
                URLQueryItem.make("count", count),
                URLQueryItem.makeArray("excludeFields", excludeFields),
                URLQueryItem.makeBoolFlag("excludeContinueWatching", excludeContinueWatching),
            ].compactMap { $0 }
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
        self.network = PlexServerNetworkClient(authToken: authToken, baseURL: baseURLServer)
    }
    
    func getContinueWatchingHub(params: HubParams? = nil) async throws -> PlexHubMediaContainer {
        let resolved = params ?? HubParams()
        return try await network.request(path: "/hubs/continueWatching", queryItems: resolved.queryItems)
    }

    func getPromotedHub(params: HubParams? = nil) async throws -> PlexHubMediaContainer {
        let resolved = params ?? HubParams()
        var queryItems = resolved.queryItems
        if resolved.count == nil {
            queryItems.append(URLQueryItem(name: "count", value: "20"))
        }
        if resolved.excludeFields == nil {
            queryItems.append(URLQueryItem(name: "excludeFields", value: "summary"))
        }
        if resolved.excludeContinueWatching == nil {
            queryItems.append(URLQueryItem(name: "excludeContinueWatching", value: "1"))
        }
        return try await network.request(path: "/hubs/promoted", queryItems: queryItems)
    }

    func getSectionHubs(sectionId: Int) async throws -> PlexHubMediaContainer {
        try await network.request(
            path: "/hubs/sections/\(sectionId)",
            queryItems: [
                URLQueryItem(name: "count", value: "20"),
                URLQueryItem(name: "excludeFields", value: "summary"),
            ]
        )
    }
    
    func getRelatedMediaHubs(ratingKey: String) async throws -> PlexHubMediaContainer {
        try await network.request(path: "/library/metadata/\(ratingKey)/related")
    }
}
