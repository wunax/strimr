import Foundation

final class SectionRepository {
    private let network: PlexServerNetworkClient
    private weak var context: PlexAPIContext?

    struct SectionItemsParams: QueryItemConvertible {
        var sort: String?
        var limit: Int?
        var includeMeta: Bool?
        var includeCollections: Bool?
        var type: String? = "1,2"

        var queryItems: [URLQueryItem] {
            [
                // "1,2" maps to movie and show.
                URLQueryItem.make("type", type),
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

    func getSectionItems(
        path: String,
        queryItems: [URLQueryItem] = [],
        pagination: PlexPagination? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolvedPagination = pagination ?? PlexPagination()
        return try await network.request(
            path: path,
            queryItems: queryItems,
            headers: resolvedPagination.headers,
        )
    }

    func getFilterOptions(
        path: String,
        queryItems: [URLQueryItem] = [],
    ) async throws -> PlexFilterMediaContainer {
        try await network.request(
            path: path,
            queryItems: queryItems,
        )
    }

    func getSectionFirstCharacters(
        sectionId: Int,
        type: Int? = nil,
        includeCollections: Bool? = nil,
    ) async throws -> PlexFirstCharacterMediaContainer {
        let queryItems = [
            URLQueryItem.make("type", type),
            URLQueryItem.makeBoolFlag("includeCollections", includeCollections),
        ].compactMap(\.self)

        return try await network.request(
            path: "/library/sections/\(sectionId)/firstCharacter",
            queryItems: queryItems,
        )
    }

    func getSectionCollections(
        sectionId: Int,
        includeCollections: Bool? = true,
        pagination: PlexPagination? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolvedPagination = pagination ?? PlexPagination()
        let queryItems = [
            URLQueryItem.makeBoolFlag("includeCollections", includeCollections),
        ].compactMap(\.self)

        return try await network.request(
            path: "/library/sections/\(sectionId)/collections",
            queryItems: queryItems,
            headers: resolvedPagination.headers,
        )
    }
}
