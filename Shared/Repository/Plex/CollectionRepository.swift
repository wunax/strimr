import Foundation

final class CollectionRepository {
    private let network: PlexServerNetworkClient

    struct PlexCollectionParams: QueryItemConvertible {
        var checkFiles: Bool?
        var includeChapters: Bool?
        var includeMarkers: Bool?
        var includeOnDeck: Bool?

        var queryItems: [URLQueryItem] {
            [
                URLQueryItem.makeBoolFlag("checkFiles", checkFiles),
                URLQueryItem.makeBoolFlag("includeChapters", includeChapters),
                URLQueryItem.makeBoolFlag("includeMarkers", includeMarkers),
                URLQueryItem.makeBoolFlag("includeOnDeck", includeOnDeck),
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

        network = PlexServerNetworkClient(authToken: authToken, baseURL: baseURLServer)
    }

    func getCollection(
        ratingKey: String,
        params: PlexCollectionParams? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolved = params ?? PlexCollectionParams()
        return try await network.request(
            path: "/library/collections/\(ratingKey)",
            queryItems: resolved.queryItems,
        )
    }

    func getCollectionChildren(
        ratingKey: String,
        params: PlexCollectionParams? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolved = params ?? PlexCollectionParams()
        return try await network.request(
            path: "/library/collections/\(ratingKey)/children",
            queryItems: resolved.queryItems,
        )
    }
}
