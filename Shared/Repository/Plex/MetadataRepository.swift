import Foundation

final class MetadataRepository {
    private let network: PlexServerNetworkClient
    private weak var context: PlexAPIContext?

    struct PlexMetadataParams: QueryItemConvertible {
        var checkFiles: Bool?
        var includeStreams: Bool?
        var includeChapters: Bool?
        var includeMarkers: Bool?
        var includeOnDeck: Bool?

        var queryItems: [URLQueryItem] {
            [
                URLQueryItem.makeBoolFlag("checkFiles", checkFiles),
                URLQueryItem.makeBoolFlag("includeStreams", includeStreams),
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

    /// The external ids of several items in one request, without their heavy elements.
    func getGuids(ratingKeys: [String]) async throws -> PlexItemMediaContainer {
        try await network.request(
            path: "/library/metadata/\(ratingKeys.joined(separator: ","))",
            queryItems: [
                HubRepository.includeGuids,
                URLQueryItem(name: "excludeElements", value: "Media,Role,Genre,Director,Writer,Country,Producer"),
            ],
        )
    }

    func getMetadataChildren(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/library/metadata/\(ratingKey)/children")
    }

    func getMetadataGrandChildren(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/library/metadata/\(ratingKey)/grandchildren")
    }

    func getMetadataExtras(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/library/metadata/\(ratingKey)/extras")
    }
}
