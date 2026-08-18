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
            let type = $0.type?.lowercased()
            let collectionType = $0.collectionType?.lowercased()
            return (type == "collectionfolder" || type == "userview")
                && ["movies", "tvshows", "boxsets", "playlists"].contains(collectionType ?? "")
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

    func resumable(
        parentID: String,
        includeTypes: String,
        limit: Int,
    ) async throws -> [JellyfinItem] {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }
        let response: JellyfinQueryResult<JellyfinItem> = try await context.get(
            path: ["Users", userID, "Items"],
            query: [
                URLQueryItem(name: "SortBy", value: "DatePlayed"),
                URLQueryItem(name: "SortOrder", value: "Descending"),
                URLQueryItem(name: "IncludeItemTypes", value: includeTypes),
                URLQueryItem(name: "Filters", value: "IsResumable"),
                URLQueryItem(name: "Limit", value: String(limit)),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: Self.cardFields),
                URLQueryItem(name: "CollapseBoxSetItems", value: "false"),
                URLQueryItem(name: "ParentId", value: parentID),
                URLQueryItem(name: "EnableImages", value: "true"),
                URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
            ],
        )
        return response.items
    }

    func nextUp(
        seriesID: String? = nil,
        parentID: String? = nil,
        limit: Int = 20,
    ) async throws -> [JellyfinItem] {
        var query = commonUserQuery + [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: Self.cardFields),
            URLQueryItem(name: "EnableResumable", value: "false"),
        ]
        if let seriesID {
            query.append(URLQueryItem(name: "SeriesId", value: seriesID))
        }
        if let parentID {
            query.append(URLQueryItem(name: "ParentId", value: parentID))
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
        limit: Int = 20,
    ) async throws -> [JellyfinItem] {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }
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
        return try await context.get(path: ["Users", userID, "Items", "Latest"], query: query)
    }

    func movieRecommendations(
        categoryLimit: Int = 6,
        itemLimit: Int = 6,
    ) async throws -> [JellyfinRecommendation] {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }
        return try await context.get(
            path: ["Movies", "Recommendations"],
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "categoryLimit", value: String(categoryLimit)),
                URLQueryItem(name: "ItemLimit", value: String(itemLimit)),
                URLQueryItem(name: "Fields", value: Self.cardFields),
                URLQueryItem(name: "ImageTypeLimit", value: "1"),
                URLQueryItem(name: "EnableImageTypes", value: "Primary,Backdrop,Banner,Thumb"),
            ],
        )
    }

    func items(
        parentID: String? = nil,
        includeTypes: String,
        searchTerm: String? = nil,
        personID: String? = nil,
        recursive: Bool = true,
        startIndex: Int = 0,
        limit: Int = 100,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        filters: [String] = [],
        isFavorite: Bool = false,
        genreIDs: Set<String> = [],
        years: Set<Int> = [],
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
            URLQueryItem(name: "SortBy", value: sortBy ?? (searchTerm == nil ? "SortName" : "SearchScore,SortName")),
            URLQueryItem(name: "SortOrder", value: sortOrder ?? "Ascending"),
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
        if !filters.isEmpty {
            query.append(URLQueryItem(name: "Filters", value: filters.joined(separator: ",")))
        }
        if isFavorite {
            query.append(URLQueryItem(name: "IsFavorite", value: "true"))
        }
        if !genreIDs.isEmpty {
            query.append(URLQueryItem(name: "GenreIds", value: genreIDs.sorted().joined(separator: "|")))
        }
        if !years.isEmpty {
            query.append(URLQueryItem(name: "Years", value: years.sorted().map(String.init).joined(separator: ",")))
        }
        return try await context.get(path: ["Users", userID, "Items"], query: query)
    }

    func browseFilterOptions(parentID: String, includeTypes: String) async throws -> LibraryBrowseFilterOptions {
        let query = commonUserQuery + [
            URLQueryItem(name: "ParentId", value: parentID),
            URLQueryItem(name: "IncludeItemTypes", value: includeTypes),
        ]
        async let current: JellyfinQueryFilters = context.get(
            path: ["Items", "Filters2"],
            query: query + [URLQueryItem(name: "Recursive", value: "true")],
        )
        async let legacy: JellyfinLegacyQueryFilters = context.get(path: ["Items", "Filters"], query: query)
        let (currentFilters, legacyFilters) = try await (current, legacy)
        return LibraryBrowseFilterOptions(
            genres: currentFilters.genres
                .map { LibraryBrowseValueOption(id: $0.id, title: $0.name) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
            years: legacyFilters.years
                .sorted(by: >)
                .map { LibraryBrowseValueOption(id: String($0), title: String($0)) },
        )
    }

    func genres(parentID: String, includeTypes: String) async throws -> [LibraryGenre] {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }
        var startIndex = 0
        let pageSize = 100
        var values: [LibraryGenre] = []

        while true {
            let response: JellyfinQueryResult<JellyfinItem> = try await context.get(
                path: ["Genres"],
                query: [
                    URLQueryItem(name: "UserId", value: userID),
                    URLQueryItem(name: "ParentId", value: parentID),
                    URLQueryItem(name: "IncludeItemTypes", value: includeTypes),
                    URLQueryItem(name: "StartIndex", value: String(startIndex)),
                    URLQueryItem(name: "Limit", value: String(pageSize)),
                    URLQueryItem(name: "SortBy", value: "SortName"),
                    URLQueryItem(name: "SortOrder", value: "Ascending"),
                    URLQueryItem(name: "EnableImages", value: "false"),
                ],
            )
            values.append(contentsOf: response.items.map { LibraryGenre(id: $0.id, title: $0.name) })
            startIndex += response.items.count
            if response.items.isEmpty || startIndex >= (response.totalRecordCount ?? startIndex) {
                break
            }
        }
        return values
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
            path: ["MediaSegments", itemID],
        )
        return response.items
    }

    func playlistItems(id: String, fields: String = Self.cardFields) async throws -> [JellyfinItem] {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }
        return try await paginatedItems(
            path: ["Playlists", id, "Items"],
            query: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "Fields", value: fields),
                URLQueryItem(name: "EnableUserData", value: "true"),
                URLQueryItem(name: "EnableImages", value: "true"),
            ],
        )
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
        case .collection:
            return try await collectionPlaybackItems(id: item.id)
                .filter(\.isPlayable)
        case .playlist:
            return try await playlistItems(id: item.id, fields: "Chapters,Trickplay")
                .filter(\.isPlayable)
        case .folder, .unknown:
            return []
        }
    }

    private func collectionPlaybackItems(id: String) async throws -> [JellyfinItem] {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }
        return try await paginatedItems(
            path: ["Users", userID, "Items"],
            query: [
                URLQueryItem(name: "ParentId", value: id),
                URLQueryItem(name: "Filters", value: "IsNotFolder"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "MediaTypes", value: "Audio,Video"),
                URLQueryItem(name: "Fields", value: "Chapters,Trickplay"),
                URLQueryItem(name: "ExcludeLocationTypes", value: "Virtual"),
                URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
                URLQueryItem(name: "CollapseBoxSetItems", value: "false"),
            ],
        )
    }

    private func paginatedItems(
        path: [String],
        query: [URLQueryItem],
        pageSize: Int = 300,
    ) async throws -> [JellyfinItem] {
        var items: [JellyfinItem] = []
        var startIndex = 0

        while true {
            let response: JellyfinQueryResult<JellyfinItem> = try await context.get(
                path: path,
                query: query + [
                    URLQueryItem(name: "StartIndex", value: String(startIndex)),
                    URLQueryItem(name: "Limit", value: String(pageSize)),
                ],
            )
            items.append(contentsOf: response.items)

            let nextIndex = startIndex + response.items.count
            if response.items.count < pageSize
                || response.totalRecordCount.map({ nextIndex >= $0 }) == true
            {
                break
            }
            startIndex = nextIndex
        }

        return items
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
        "Trickplay", "Taglines", "OfficialRating", "CommunityRating", "CriticRating",
    ].joined(separator: ",")

    static let playbackFields = [
        cardFields, "MediaSources", "MediaStreams", "Chapters", "Trickplay",
    ].joined(separator: ",")
}
