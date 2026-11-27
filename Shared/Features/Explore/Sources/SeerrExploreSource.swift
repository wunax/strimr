import Foundation

@MainActor
final class SeerrExploreSource: ExploreSource {
    let id = ExploreSourceID.seerr
    let rows: [ExploreRowID] = [.trending, .popularMovies, .upcomingMovies, .popularShows, .upcomingShows]
    let watchlist: ExploreWatchlist? = nil

    private let baseURL: URL
    private let now: () -> Date

    init(baseURL: URL, now: @escaping () -> Date = Date.init) {
        self.baseURL = baseURL
        self.now = now
    }

    func fetchRow(_ row: ExploreRowID, page: Int) async throws -> ExplorePage {
        let repository = SeerrDiscoverRepository(baseURL: baseURL)
        let upcomingDate = Self.dateFormatter.string(from: now())
        let response: SeerrPaginatedResponse<SeerrMedia>
        let kind: ExploreItemKind?
        switch row {
        case .trending:
            response = try await repository.getTrending(page: page)
            kind = nil
        case .popularMovies:
            response = try await repository.discoverMovies(page: page)
            kind = .movie
        case .upcomingMovies:
            response = try await repository.discoverMovies(page: page, primaryReleaseDateGte: upcomingDate)
            kind = .movie
        case .popularShows:
            response = try await repository.discoverTV(page: page)
            kind = .show
        case .upcomingShows:
            response = try await repository.discoverTV(page: page, firstAirDateGte: upcomingDate)
            kind = .show
        case .watchlist, .recommendedMovies, .recommendedShows, .trendingMovies, .trendingShows:
            return ExplorePage(items: [])
        }
        return ExplorePage(
            items: response.results.compactMap { Self.item(from: $0, kind: kind) },
            hasMore: response.page < response.totalPages,
        )
    }

    func search(_ query: String) async throws -> [ExploreItem] {
        let response = try await SeerrDiscoverRepository(baseURL: baseURL).search(query: query, page: 1)
        return response.results.compactMap { Self.item(from: $0, kind: nil) }
    }

    /// People are left out. Discover lists may omit the type, which their row then gives.
    static func item(from media: SeerrMedia, kind: ExploreItemKind?) -> ExploreItem? {
        let resolvedKind: ExploreItemKind
        switch media.mediaType {
        case .movie: resolvedKind = .movie
        case .tv: resolvedKind = .show
        case .person: return nil
        case nil:
            guard let kind else { return nil }
            resolvedKind = kind
        }
        var media = media
        media.mediaType = resolvedKind.seerrType
        return ExploreItem(
            source: .seerr,
            sourceID: String(media.id),
            kind: resolvedKind,
            title: media.displayTitle,
            year: media.year,
            overview: media.overview,
            posterURL: TMDBImageService.posterURL(path: media.posterPath, width: 500),
            backdropURL: TMDBImageService.backdropURL(path: media.backdropPath, width: 1400),
            externalIDs: ExternalIDs(
                tmdb: String(media.id),
                tvdb: media.externalIds?.tvdbId.map(String.init),
            ),
            seerrMedia: media,
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
