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
        guard context.baseURLServer != nil else {
            throw PlexAPIError.missingConnection
        }

        guard context.authTokenServer != nil else {
            throw PlexAPIError.missingAuthToken
        }

        network = PlexServerNetworkClient(context: context)
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
