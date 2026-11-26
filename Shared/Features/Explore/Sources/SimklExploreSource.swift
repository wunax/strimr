import Foundation

@MainActor
final class SimklExploreSource: ExploreSource {
    let id = ExploreSourceID.simkl
    let rows: [ExploreRowID] = [.trendingMovies, .trendingShows]
    private(set) var watchlist: ExploreWatchlist?

    private let client: SimklClient

    init(client: SimklClient) {
        self.client = client
        watchlist = ExploreWatchlist(
            fetch: { try await Self.planToWatch(client: client) },
            mutate: { add, target in
                if add {
                    try await client.post(path: "sync/add-to-list", body: Self.addBody(target))
                    return
                }
                // Simkl has no way to take a title off a list: removing it from the history drops it from every
                // list, watch history included. A title that has moved on from Plan to Watch is left alone.
                let planned = try await Self.planToWatch(client: client)
                let plannedKeys = planned.reduce(into: Set<String>()) { $0.formUnion($1.watchlistTarget.keys) }
                guard Self.isPlanned(target, keys: plannedKeys) else { return }
                try await client.post(path: "sync/history/remove", body: Self.removeBody(target))
            },
        )
    }

    func fetchRow(_ row: ExploreRowID, page: Int) async throws -> ExplorePage {
        // The trending lists come whole, as a single page.
        guard page == 1 else { return ExplorePage(items: []) }
        switch row {
        case .trendingMovies:
            let response = try await client.publicData("discover/trending/movies/week_100.json")
            return try ExplorePage(items: Self.trending(response.data, kind: .movie))
        case .trendingShows:
            let response = try await client.publicData("discover/trending/tv/week_100.json")
            return try ExplorePage(items: Self.trending(response.data, kind: .show))
        default:
            return ExplorePage(items: [])
        }
    }

    func search(_ query: String) async throws -> [ExploreItem] {
        async let movies = client.get("search/movie", query: Self.searchQuery(query))
        async let shows = client.get("search/tv", query: Self.searchQuery(query))
        return try await Self.searchResults(movies.data, kind: .movie) + Self.searchResults(shows.data, kind: .show)
    }

    /// Simkl takes imdb, tmdb and tvdb ids directly.
    func watchlistTarget(kind: ExploreItemKind, externalIDs: ExternalIDs, plexGuidID _: String?) async throws
        -> ExploreWatchlistTarget?
    {
        guard !externalIDs.isEmpty else { return nil }
        return ExploreWatchlistTarget(kind: kind, externalIDs: externalIDs)
    }

    private static func searchQuery(_ query: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "extended", value: "full"),
        ]
    }

    private static func planToWatch(client: SimklClient) async throws -> [ExploreItem] {
        let response = try await client.get("sync/all-items/all/plantowatch", query: [
            URLQueryItem(name: "extended", value: "full"),
        ])
        return try watchlistItems(response.data)
    }

    static func isPlanned(_ target: ExploreWatchlistTarget, keys: Set<String>) -> Bool {
        !target.keys.isDisjoint(with: keys)
    }

    // MARK: - Mapping

    /// Ids come as numbers or strings depending on the endpoint, and the CDN names Simkl's own `simkl_id`.
    struct IDs: Decodable {
        let simkl: String?
        let imdb: String?
        let tmdb: String?
        let tvdb: String?

        private enum CodingKeys: String, CodingKey {
            case simkl
            case simklID = "simkl_id"
            case imdb
            case tmdb
            case tvdb
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            simkl = Self.string(container, .simkl) ?? Self.string(container, .simklID)
            imdb = Self.string(container, .imdb)
            tmdb = Self.string(container, .tmdb)
            tvdb = Self.string(container, .tvdb)
        }

        private static func string(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
            if let value = try? container.decode(String.self, forKey: key) {
                return value
            }
            return (try? container.decode(Int.self, forKey: key)).map(String.init)
        }
    }

    struct Media: Decodable {
        let title: String?
        let year: Int?
        let overview: String?
        let poster: String?
        let fanart: String?
        let releaseDate: String?
        let ids: IDs

        private enum CodingKeys: String, CodingKey {
            case title
            case year
            case overview
            case poster
            case fanart
            case releaseDate = "release_date"
            case ids
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try? container.decodeIfPresent(String.self, forKey: .title)
            year = (try? container.decodeIfPresent(Int.self, forKey: .year))
                ?? (try? container.decodeIfPresent(String.self, forKey: .year)).flatMap { $0.flatMap(Int.init) }
            overview = try? container.decodeIfPresent(String.self, forKey: .overview)
            poster = try? container.decodeIfPresent(String.self, forKey: .poster)
            fanart = try? container.decodeIfPresent(String.self, forKey: .fanart)
            releaseDate = try? container.decodeIfPresent(String.self, forKey: .releaseDate)
            ids = try container.decode(IDs.self, forKey: .ids)
        }

        /// The CDN gives `MM/DD/YYYY` release dates and no year.
        var resolvedYear: Int? {
            year ?? releaseDate?.split(separator: "/").last.flatMap { Int($0) }
        }
    }

    struct WatchlistEntry: Decodable {
        let movie: Media?
        let show: Media?
        let animeType: String?

        private enum CodingKeys: String, CodingKey {
            case movie
            case show
            case animeType = "anime_type"
        }
    }

    struct AllItems: Decodable {
        let movies: [WatchlistEntry]?
        let shows: [WatchlistEntry]?
        let anime: [WatchlistEntry]?
    }

    static func watchlistItems(_ data: Data) throws -> [ExploreItem] {
        // An empty list comes back as `null`.
        guard let all = try? JSONDecoder().decode(AllItems.self, from: data) else {
            if String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
                return []
            }
            throw TrackerAPIError.invalidResponse
        }
        let movies = (all.movies ?? []).compactMap { $0.movie.flatMap { item(from: $0, kind: .movie) } }
        let shows = (all.shows ?? []).compactMap { $0.show.flatMap { item(from: $0, kind: .show) } }
        let anime = (all.anime ?? []).compactMap { entry -> ExploreItem? in
            let kind: ExploreItemKind = entry.animeType == "movie" ? .movie : .show
            return (entry.show ?? entry.movie).flatMap { item(from: $0, kind: kind) }
        }
        return movies + shows + anime
    }

    static func trending(_ data: Data, kind: ExploreItemKind) throws -> [ExploreItem] {
        try decode([Media].self, from: data).compactMap { item(from: $0, kind: kind) }
    }

    static func searchResults(_ data: Data, kind: ExploreItemKind) throws -> [ExploreItem] {
        try decode([Media].self, from: data).compactMap { item(from: $0, kind: kind) }
    }

    static func item(from media: Media, kind: ExploreItemKind) -> ExploreItem? {
        guard let simklID = media.ids.simkl, let title = media.title, !title.isEmpty else { return nil }
        return ExploreItem(
            source: .simkl,
            sourceID: simklID,
            kind: kind,
            title: title,
            year: media.resolvedYear,
            overview: media.overview,
            posterURL: media.poster.flatMap { URL(string: "https://simkl.in/posters/\($0)_m.webp") },
            backdropURL: media.fanart.flatMap { URL(string: "https://simkl.in/fanart/\($0)_medium.webp") },
            externalIDs: ExternalIDs(imdb: media.ids.imdb, tmdb: media.ids.tmdb, tvdb: media.ids.tvdb),
        )
    }

    private static func ids(_ target: ExploreWatchlistTarget) -> [String: Any] {
        var ids: [String: Any] = [:]
        ids["simkl"] = target.sourceID.flatMap(Int.init)
        ids["imdb"] = target.externalIDs.imdb
        ids["tmdb"] = target.externalIDs.tmdb
        ids["tvdb"] = target.externalIDs.tvdb
        return ids
    }

    static func addBody(_ target: ExploreWatchlistTarget) -> [String: Any] {
        [target.kind == .movie ? "movies" : "shows": [["to": "plantowatch", "ids": ids(target)]]]
    }

    static func removeBody(_ target: ExploreWatchlistTarget) -> [String: Any] {
        [target.kind == .movie ? "movies" : "shows": [["ids": ids(target)]]]
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TrackerAPIError.invalidResponse
        }
    }
}
