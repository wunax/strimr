import Foundation

final class SearchRepository {
    enum SearchType: String {
        case movies
        case tv
    }

    struct SearchParams: QueryItemConvertible {
        var query: String
        var searchTypes: [SearchType]
        var limit: Int?

        var queryItems: [URLQueryItem] {
            [
                URLQueryItem(name: "query", value: query),
                URLQueryItem.makeArray("searchTypes", searchTypes.map(\.rawValue)),
                URLQueryItem.make("limit", limit),
            ].compactMap(\.self)
        }
    }

    private let network: PlexServerNetworkClient

    init(context: PlexAPIContext) throws {
        guard context.baseURLServer != nil else {
            throw PlexAPIError.missingConnection
        }

        guard context.authTokenServer != nil else {
            throw PlexAPIError.missingAuthToken
        }

        network = PlexServerNetworkClient(context: context)
    }

    func search(params: SearchParams) async throws -> PlexSearchMediaContainer {
        try await network.request(path: "/library/search", queryItems: params.queryItems)
    }
}
