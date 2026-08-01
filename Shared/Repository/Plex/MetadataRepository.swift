import Foundation

final class MetadataRepository {
    private let network: PlexServerNetworkClient
    private weak var context: PlexAPIContext?

    struct PlexMetadataParams: QueryItemConvertible {
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

        self.context = context
        network = PlexServerNetworkClient(context: context)
    }

    func getMetadata(
        ratingKey: String,
        params: PlexMetadataParams? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolved = params ?? PlexMetadataParams()
        return try await network.request(path: "/library/metadata/\(ratingKey)", queryItems: resolved.queryItems)
    }

    func getMetadataChildren(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/library/metadata/\(ratingKey)/children")
    }

    func getMetadataGrandChildren(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/library/metadata/\(ratingKey)/grandchildren")
    }
}
