import Foundation

@MainActor
struct JellyfinCatalogService {
    private let context: JellyfinAPIContext

    init(context: JellyfinAPIContext) {
        self.context = context
    }

    func libraries() async throws -> [JellyfinItem] {
        let response: JellyfinQueryResult<JellyfinItem> = try await context.get(
            path: ["UserViews"],
            query: commonUserQuery,
        )
        return response.items.filter {
            $0.type?.lowercased() == "collectionfolder"
                && ($0.collectionType == "movies" || $0.collectionType == "tvshows")
        }
    }

    func resume(limit: Int = 20) async throws -> [JellyfinItem] {
        let response: JellyfinQueryResult<JellyfinItem> = try await context.get(
            path: ["UserItems", "Resume"],
            query: commonUserQuery + [
                URLQueryItem(name: "IncludeItemTypes", value: "Movie,Episode"),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "Fields", value: Self.cardFields),
                URLQueryItem(name: "MediaTypes", value: "Video"),
            ],
        )
        return response.items
    }

    func nextUp(seriesID: String? = nil, limit: Int = 20) async throws -> [JellyfinItem] {
        var query = commonUserQuery + [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: Self.cardFields),
            URLQueryItem(name: "EnableResumable", value: "false"),
        ]
        if let seriesID {
            query.append(URLQueryItem(name: "SeriesId", value: seriesID))
        }
        let response: JellyfinQueryResult<JellyfinItem> = try await context.get(
            path: ["Shows", "NextUp"],
            query: query,
        )
        return response.items
    }

    func latest(
        types: String? = nil,
        parentID: String? = nil,
        limit: Int = 20
    ) async throws -> [JellyfinItem] {
        var query = commonUserQuery + [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: Self.cardFields),
            URLQueryItem(name: "EnableImages", value: "true"),
        ]
        if let types {
            query.append(URLQueryItem(name: "IncludeItemTypes", value: types))
        }
        if let parentID {
            query.append(URLQueryItem(name: "ParentId", value: parentID))
        }
        return try await context.get(path: ["Items", "Latest"], query: query)
    }

    func items(
        parentID: String? = nil,
        includeTypes: String,
        searchTerm: String? = nil,
        personID: String? = nil,
        recursive: Bool = true,
        startIndex: Int = 0,
        limit: Int = 100,
    ) async throws -> JellyfinQueryResult<JellyfinItem> {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }
        var query = [
            URLQueryItem(name: "Recursive", value: recursive ? "true" : "false"),
            URLQueryItem(name: "IncludeItemTypes", value: includeTypes),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: Self.cardFields),
            URLQueryItem(name: "EnableUserData", value: "true"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "SortBy", value: searchTerm == nil ? "SortName" : "SearchScore,SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
        ]
        if let parentID {
            query.append(URLQueryItem(name: "ParentId", value: parentID))
        }
        if let searchTerm, !searchTerm.isEmpty {
            query.append(URLQueryItem(name: "SearchTerm", value: searchTerm))
        }
        if let personID {
            query.append(URLQueryItem(name: "PersonIds", value: personID))
        }
        return try await context.get(path: ["Users", userID, "Items"], query: query)
    }

    func item(id: String) async throws -> JellyfinItem {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }
        return try await context.get(
            path: ["Users", userID, "Items", id],
            query: [URLQueryItem(name: "Fields", value: Self.detailFields)],
        )
    }

    func seasons(seriesID: String) async throws -> [JellyfinItem] {
        let response: JellyfinQueryResult<JellyfinItem> = try await context.get(
            path: ["Shows", seriesID, "Seasons"],
            query: commonUserQuery + [
                URLQueryItem(name: "Fields", value: Self.cardFields),
                URLQueryItem(name: "EnableUserData", value: "true"),
            ],
        )
        return response.items
    }

    func episodes(
        seriesID: String,
        seasonID: String? = nil,
        startItemID: String? = nil,
    ) async throws -> [JellyfinItem] {
        var query = commonUserQuery + [
            URLQueryItem(name: "Fields", value: Self.playbackFields),
            URLQueryItem(name: "EnableUserData", value: "true"),
            URLQueryItem(name: "Limit", value: "500"),
        ]
        if let seasonID {
            query.append(URLQueryItem(name: "SeasonId", value: seasonID))
        }
        if let startItemID {
            query.append(URLQueryItem(name: "StartItemId", value: startItemID))
        }
        let response: JellyfinQueryResult<JellyfinItem> = try await context.get(
            path: ["Shows", seriesID, "Episodes"],
            query: query,
        )
        guard let startItemID, let index = response.items.firstIndex(where: { $0.id == startItemID }) else {
            return response.items
        }
        return Array(response.items[index...])
    }

    func similar(itemID: String, limit: Int = 20) async throws -> [JellyfinItem] {
        let response: JellyfinQueryResult<JellyfinItem> = try await context.get(
            path: ["Items", itemID, "Similar"],
            query: commonUserQuery + [
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "Fields", value: Self.cardFields),
            ],
        )
        return response.items
    }

    func markPlayed(itemID: String, played: Bool) async throws {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }
        try await context.send(
            path: ["Users", userID, "PlayedItems", itemID],
            method: played ? "POST" : "DELETE",
        )
    }

    func mediaSegments(itemID: String) async throws -> [JellyfinMediaSegment] {
        let response: JellyfinMediaSegmentsResponse = try await context.get(
            path: ["MediaSegments", itemID]
        )
        return response.items
    }

    func playbackQueue(startingWith item: JellyfinItem) async throws -> [JellyfinItem] {
        switch item.kind {
        case .movie:
            return [item]
        case .episode:
            guard let seriesID = item.seriesID else { return [item] }
            let queue = try await episodes(seriesID: seriesID, startItemID: item.id)
            return queue.isEmpty ? [item] : queue
        case .season:
            guard let seriesID = item.seriesID ?? item.parentID else { return [] }
            return try await episodes(seriesID: seriesID, seasonID: item.id)
        case .series:
            if let next = try await nextUp(seriesID: item.id, limit: 1).first {
                return try await episodes(seriesID: item.id, startItemID: next.id)
            }
            return try await episodes(seriesID: item.id)
        case .collection, .playlist:
            return try await items(
                parentID: item.id,
                includeTypes: "Movie,Episode",
                recursive: false,
                limit: 500,
            ).items
        case .folder, .unknown:
            return []
        }
    }

    private var commonUserQuery: [URLQueryItem] {
        guard let userID = context.connection?.userID else { return [] }
        return [URLQueryItem(name: "UserId", value: userID)]
    }

    static let cardFields = [
        "Overview", "PrimaryImageAspectRatio", "UserData", "ProductionYear", "RunTimeTicks",
        "ChildCount", "RecursiveItemCount", "ParentId", "SeriesId", "SeasonId", "SeriesName",
        "SeasonName", "ParentIndexNumber", "IndexNumber", "MediaSources",
    ].joined(separator: ",")

    static let detailFields = [
        cardFields, "Genres", "Studios", "People", "ProviderIds", "MediaStreams", "Chapters",
        "Trickplay", "Taglines", "OfficialRating",
    ].joined(separator: ",")

    static let playbackFields = [
        cardFields, "MediaSources", "MediaStreams", "Chapters", "Trickplay",
    ].joined(separator: ",")
}
