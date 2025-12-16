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
            ].compactMap { $0 }
        }
    }

    private let network: PlexServerNetworkClient

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }

        network = PlexServerNetworkClient(authToken: authToken, baseURL: baseURLServer)
    }

    func search(params: SearchParams) async throws -> PlexSearchMediaContainer {
        try await network.request(path: "/library/search", queryItems: params.queryItems)
    }
}
