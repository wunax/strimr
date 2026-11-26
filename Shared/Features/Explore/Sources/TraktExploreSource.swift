import Foundation

@MainActor
final class TraktExploreSource: ExploreSource {
    let id = ExploreSourceID.trakt
    let rows: [ExploreRowID] = [
        .recommendedMovies, .recommendedShows, .trendingMovies, .trendingShows, .popularMovies, .popularShows,
    ]
    private(set) var watchlist: ExploreWatchlist?

    static let pageSize = 25
    private static let extended = URLQueryItem(name: "extended", value: "full,images")

    private let client: TraktClient

    init(client: TraktClient) {
        self.client = client
        watchlist = ExploreWatchlist(
            fetch: {
                async let movies = client.get("sync/watchlist/movies", query: [Self.extended])
                async let shows = client.get("sync/watchlist/shows", query: [Self.extended])
                return try await Self.entries(movies.data) + Self.entries(shows.data)
            },
            mutate: { add, target in
                guard let body = Self.watchlistBody(target) else { return }
                try await client.post(path: add ? "sync/watchlist" : "sync/watchlist/remove", body: body)
            },
        )
    }

    func fetchRow(_ row: ExploreRowID, page: Int) async throws -> ExplorePage {
        let paging = [
            Self.extended,
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
        ]
        switch row {
        case .recommendedMovies, .recommendedShows:
            // Recommendations take a limit but no page.
            guard page == 1 else { return ExplorePage(items: []) }
            let type = row == .recommendedMovies ? "movies" : "shows"
            let response = try await client.get("recommendations/\(type)", query: [
                Self.extended,
                URLQueryItem(name: "limit", value: String(Self.pageSize)),
                URLQueryItem(name: "ignore_watchlisted", value: "true"),
            ])
            return try ExplorePage(items: Self.media(response.data, kind: row == .recommendedMovies ? .movie : .show))
        case .trendingMovies, .trendingShows:
            let kind: ExploreItemKind = row == .trendingMovies ? .movie : .show
            let response = try await client.get("\(kind == .movie ? "movies" : "shows")/trending", query: paging)
            return try ExplorePage(items: Self.entries(response.data), hasMore: Self.hasMore(response, page: page))
        case .popularMovies, .popularShows:
            let kind: ExploreItemKind = row == .popularMovies ? .movie : .show
            let response = try await client.get("\(kind == .movie ? "movies" : "shows")/popular", query: paging)
            return try ExplorePage(
                items: Self.media(response.data, kind: kind),
                hasMore: Self.hasMore(response, page: page),
            )
        case .watchlist, .trending, .upcomingMovies, .upcomingShows:
            return ExplorePage(items: [])
        }
    }

    func search(_ query: String) async throws -> [ExploreItem] {
        let response = try await client.get("search/movie,show", query: [
            URLQueryItem(name: "query", value: query),
            Self.extended,
            URLQueryItem(name: "limit", value: "30"),
        ])
        return try Self.entries(response.data)
    }

    func detail(of item: ExploreItem) async throws -> ExploreDetail {
        let type = item.kind == .movie ? "movies" : "shows"
        let response = try? await client.get("\(type)/\(item.sourceID)/related", query: [
            Self.extended,
            URLQueryItem(name: "limit", value: "20"),
        ])
        let related = (response.flatMap { try? Self.media($0.data, kind: item.kind) }) ?? []
        return ExploreDetail(item: item, related: related)
    }

    /// Trakt takes imdb, tmdb and tvdb ids directly, so a server item needs no lookup.
    func watchlistTarget(kind: ExploreItemKind, externalIDs: ExternalIDs, plexGuidID _: String?) async throws
        -> ExploreWatchlistTarget?
    {
        guard !externalIDs.isEmpty else { return nil }
        return ExploreWatchlistTarget(kind: kind, externalIDs: externalIDs)
    }

    private static func hasMore(_ response: TrackerHTTPResponse, page: Int) -> Bool {
        (response.pageCount ?? page) > page
    }

    // MARK: - Mapping

    struct Media: Decodable {
        struct IDs: Decodable {
            let trakt: Int?
            let imdb: String?
            let tmdb: Int?
            let tvdb: Int?
        }

        struct Images: Decodable {
            let poster: [String]?
            let fanart: [String]?
            let thumb: [String]?
        }

        let title: String?
        let year: Int?
        let overview: String?
        let ids: IDs?
        let images: Images?
    }

    /// Lists and searches wrap each title with its type: `{type, movie}` or `{type, show}`.
    struct Entry: Decodable {
        let movie: Media?
        let show: Media?
    }

    static func entries(_ data: Data) throws -> [ExploreItem] {
        try decode([Entry].self, from: data).compactMap { entry in
            if let movie = entry.movie {
                return item(from: movie, kind: .movie)
            }
            return entry.show.flatMap { item(from: $0, kind: .show) }
        }
    }

    static func media(_ data: Data, kind: ExploreItemKind) throws -> [ExploreItem] {
        try decode([Media].self, from: data).compactMap { item(from: $0, kind: kind) }
    }

    static func item(from media: Media, kind: ExploreItemKind) -> ExploreItem? {
        guard let traktID = media.ids?.trakt, let title = media.title, !title.isEmpty else { return nil }
        return ExploreItem(
            source: .trakt,
            sourceID: String(traktID),
            kind: kind,
            title: title,
            year: media.year,
            overview: media.overview,
            posterURL: imageURL(media.images?.poster),
            backdropURL: imageURL(media.images?.fanart) ?? imageURL(media.images?.thumb),
            externalIDs: ExternalIDs(
                imdb: media.ids?.imdb,
                tmdb: media.ids?.tmdb.map(String.init),
                tvdb: media.ids?.tvdb.map(String.init),
            ),
        )
    }

    /// Trakt image urls have no scheme.
    static func imageURL(_ urls: [String]?) -> URL? {
        guard let url = urls?.first, !url.isEmpty else { return nil }
        return URL(string: url.hasPrefix("http") ? url : "https://\(url)")
    }

    /// Trakt wants numeric tmdb and tvdb ids.
    static func watchlistBody(_ target: ExploreWatchlistTarget) -> [String: Any]? {
        var ids: [String: Any] = [:]
        ids["trakt"] = target.sourceID.flatMap(Int.init)
        ids["imdb"] = target.externalIDs.imdb
        ids["tmdb"] = target.externalIDs.tmdb.flatMap(Int.init)
        ids["tvdb"] = target.externalIDs.tvdb.flatMap(Int.init)
        guard !ids.isEmpty else { return nil }
        return [target.kind == .movie ? "movies" : "shows": [["ids": ids]]]
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TrackerAPIError.invalidResponse
        }
    }
}
