import Foundation

final class SectionRepository {
    private let network: PlexServerNetworkClient
    private weak var context: PlexAPIContext?

    struct SectionItemsParams: QueryItemConvertible {
        var sort: String?
        var limit: Int?
        var includeMeta: Bool?
        var includeCollections: Bool? = nil

        var queryItems: [URLQueryItem] {
            [
                // "1,2" maps to movie and show.
                URLQueryItem(name: "type", value: "1,2"),
                URLQueryItem.make("sort", sort),
                URLQueryItem.make("limit", limit),
                URLQueryItem.makeBoolFlag("includeMeta", includeMeta),
                URLQueryItem.makeBoolFlag("includeCollections", includeCollections),
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

    func getSections() async throws -> PlexSectionMediaContainer {
        try await network.request(path: "/library/sections/all")
    }

    func getSectionsItems(
        sectionId: Int,
        params: SectionItemsParams? = nil,
        pagination: PlexPagination? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolvedParams = params ?? SectionItemsParams()
        let resolvedPagination = pagination ?? PlexPagination()
        return try await network.request(
            path: "/library/sections/\(sectionId)/all",
            queryItems: resolvedParams.queryItems,
            headers: resolvedPagination.headers,
        )
    }

    func getSectionsItemsMeta(sectionId: Int) async throws -> PlexSectionMetaMediaContainer {
        try await network.request(
            path: "/library/sections/\(sectionId)/all",
            queryItems: SectionItemsParams(includeMeta: true).queryItems,
            headers: PlexPagination(start: 0, size: 0).headers,
        )
    }

    func getSectionsItemsMetaInfo(sectionId: Int, filter: String) async throws -> PlexDirectoryMediaContainer {
        try await network.request(path: "/library/sections/\(sectionId)/\(filter)")
    }

    func getSectionFirstCharacters(sectionId: Int) async throws -> PlexFirstCharacterMediaContainer {
        try await network.request(path: "/library/sections/\(sectionId)/firstCharacter")
    }
}
