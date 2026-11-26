import Foundation

/// Sources in their default priority: the first connected one is shown until the user picks another.
enum ExploreSourceID: String, CaseIterable, Codable, Hashable, Sendable {
    case seerr
    case plex
    case trakt
    case simkl

    var displayName: String {
        switch self {
        case .seerr: "Seerr"
        case .plex: "Plex"
        case .trakt: "Trakt"
        case .simkl: "Simkl"
        }
    }

    var systemImage: String {
        switch self {
        case .seerr: "sparkles"
        case .plex: "play.rectangle.fill"
        case .trakt: "checkmark.seal.fill"
        case .simkl: "list.bullet.rectangle.fill"
        }
    }
}

enum ExploreItemKind: String, Codable, Hashable, Sendable {
    case movie
    case show

    var mediaKind: MediaKind {
        self == .movie ? .movie : .series
    }

    var matchKind: MediaMatchDescriptor.Kind {
        self == .movie ? .movie : .series
    }

    var seerrType: SeerrMediaType {
        self == .movie ? .movie : .tv
    }

    init?(mediaKind: MediaKind) {
        switch mediaKind {
        case .movie: self = .movie
        case .series: self = .show
        default: return nil
        }
    }
}

enum ExploreRowID: String, CaseIterable, Hashable, Sendable {
    case watchlist
    case recommendedMovies
    case recommendedShows
    case trending
    case trendingMovies
    case trendingShows
    case popularMovies
    case popularShows
    case upcomingMovies
    case upcomingShows

    var title: String {
        switch self {
        case .watchlist: String(localized: "explore.rows.watchlist")
        case .recommendedMovies: String(localized: "explore.rows.recommendedMovies")
        case .recommendedShows: String(localized: "explore.rows.recommendedShows")
        case .trending: String(localized: "explore.rows.trending")
        case .trendingMovies: String(localized: "explore.rows.trendingMovies")
        case .trendingShows: String(localized: "explore.rows.trendingShows")
        case .popularMovies: String(localized: "explore.rows.popularMovies")
        case .popularShows: String(localized: "explore.rows.popularShows")
        case .upcomingMovies: String(localized: "explore.rows.upcomingMovies")
        case .upcomingShows: String(localized: "explore.rows.upcomingShows")
        }
    }
}

/// A title from an external catalog. The same film seen from two sources is two items.
struct ExploreItem: Identifiable, Hashable {
    let source: ExploreSourceID
    /// The source's own id: Discover rating key, Trakt or Simkl id, TMDB id for Seerr.
    let sourceID: String
    let kind: ExploreItemKind
    var title: String
    var originalTitle: String?
    var year: Int?
    var overview: String?
    var posterURL: URL?
    var backdropURL: URL?
    var externalIDs: ExternalIDs
    /// Plex Discover guids (`plex://movie/…`) are shared with Plex servers, which makes them a match key.
    var plexGuid: String?
    /// Seerr items keep their payload so the Seerr page opens with what the rail already knows.
    var seerrMedia: SeerrMedia?

    var id: String {
        "\(source.rawValue):\(kind.rawValue):\(sourceID)"
    }

    var matchDescriptor: MediaMatchDescriptor {
        MediaMatchDescriptor(kind: kind.matchKind, guid: plexGuid, externalIDs: externalIDs)
    }

    var watchlistTarget: ExploreWatchlistTarget {
        ExploreWatchlistTarget(kind: kind, externalIDs: externalIDs, sourceID: sourceID)
    }

    var tmdbID: Int? {
        externalIDs.tmdb.flatMap(Int.init)
    }

    var seerrStatus: SeerrMediaStatus? {
        seerrMedia?.mediaInfo?.status
    }

    /// Fills what a richer copy of the same item knows, keeping what this one already had.
    func enriched(with other: ExploreItem) -> ExploreItem {
        var item = self
        item.title = other.title.isEmpty ? title : other.title
        item.originalTitle = other.originalTitle ?? originalTitle
        item.year = other.year ?? year
        item.overview = other.overview ?? overview
        item.posterURL = other.posterURL ?? posterURL
        item.backdropURL = other.backdropURL ?? backdropURL
        item.externalIDs = ExternalIDs(
            imdb: externalIDs.imdb ?? other.externalIDs.imdb,
            tmdb: externalIDs.tmdb ?? other.externalIDs.tmdb,
            tvdb: externalIDs.tvdb ?? other.externalIDs.tvdb,
        )
        item.plexGuid = plexGuid ?? other.plexGuid
        item.seerrMedia = seerrMedia ?? other.seerrMedia
        return item
    }
}

struct ExplorePage {
    var items: [ExploreItem]
    var hasMore = false
}

/// A rail the source defines at runtime, with its own title.
struct ExploreHub: Identifiable {
    let id: String
    let title: String
    let page: ExplorePage
}

struct ExploreDetail {
    var item: ExploreItem
    var related: [ExploreItem] = []
}

/// What a watchlist needs to recognize or change a title, in a source's terms.
struct ExploreWatchlistTarget: Hashable {
    let kind: ExploreItemKind
    let externalIDs: ExternalIDs
    /// The source's own id, when known.
    var sourceID: String?

    /// Any shared key means the same title. The kind is part of each key, as tmdb ids of movies and shows overlap.
    var keys: Set<String> {
        var keys = Set<String>()
        let scope = kind.rawValue
        if let sourceID {
            keys.insert("\(scope):id:\(sourceID)")
        }
        if let imdb = externalIDs.imdb {
            keys.insert("\(scope):imdb:\(imdb)")
        }
        if let tmdb = externalIDs.tmdb {
            keys.insert("\(scope):tmdb:\(tmdb)")
        }
        if let tvdb = externalIDs.tvdb {
            keys.insert("\(scope):tvdb:\(tvdb)")
        }
        return keys
    }
}

/// One source's watchlist action for a server item.
struct ExploreWatchlistOption: Identifiable {
    let source: ExploreSourceID
    let target: ExploreWatchlistTarget
    let watchlist: ExploreWatchlist

    var id: ExploreSourceID {
        source
    }

    @MainActor
    var isOnWatchlist: Bool {
        watchlist.contains(target) ?? false
    }

    @MainActor
    var isUpdating: Bool {
        watchlist.isUpdating(target)
    }

    @MainActor
    var title: String {
        isOnWatchlist
            ? String(localized: "explore.watchlist.remove \(source.displayName)")
            : String(localized: "explore.watchlist.add \(source.displayName)")
    }

    @MainActor
    var systemImage: String {
        isOnWatchlist ? "bookmark.slash" : "bookmark"
    }
}
