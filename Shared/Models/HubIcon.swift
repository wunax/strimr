import Foundation

enum HubIcon {
    static func systemImage(for row: HomeRow) -> String? {
        switch row.kind {
        case .continueWatching:
            "play.circle"
        case .nextUp:
            "forward.end.circle"
        case .hub:
            systemImage(for: row.hub)
        }
    }

    static func systemImage(for hub: Hub) -> String? {
        let symbol: String? = switch hub.server?.provider {
        case .plex:
            plexSystemImage(hubID: hub.id)
        case .jellyfin:
            jellyfinSystemImage(hubID: hub.id)
        case nil:
            nil
        }
        return symbol ?? contentSystemImage(for: hub.items)
    }

    /// Plex hub ids are stable, unlocalized words such as `movie.recentlyadded.1` or `tv.moreingenre.2`. Whole words
    /// are matched so `recentlyaired` is not taken for `recent`, and numeric variants are ignored.
    private static func plexSystemImage(hubID: String) -> String? {
        let words = Set(hubID.lowercased().split(separator: ".").map(String.init))
        return plexWordSymbols.first { !words.isDisjoint(with: $0.words) }?.symbol
    }

    private static let plexWordSymbols: [(words: Set<String>, symbol: String)] = [
        (["continue", "inprogress"], "play.circle"),
        (["ondeck"], "forward.end.circle"),
        (["recentlyreleased", "recentlyaired"], "calendar"),
        (["recentlyviewed"], "eye"),
        (["recentlyadded", "recent"], "clock"),
        (["trending"], "chart.line.uptrend.xyaxis"),
        (["popular"], "flame"),
        (["toprated"], "star"),
        (["topunwatched"], "rosette"),
        (["genre", "moreingenre"], "theatermasks"),
        (["actor", "director"], "person"),
        (["decade", "year"], "hourglass"),
        (["startwatching"], "play"),
        (["rediscover"], "arrow.counterclockwise"),
        (["network", "studio"], "antenna.radiowaves.left.and.right"),
        (["collection"], "square.stack"),
    ]

    /// Jellyfin hub ids are built by the app and end with a library or category id, so only their prefix is matched.
    private static func jellyfinSystemImage(hubID: String) -> String? {
        jellyfinPrefixSymbols.first { hubID.hasPrefix($0.prefix) }?.symbol
    }

    private static let jellyfinPrefixSymbols: [(prefix: String, symbol: String)] = [
        ("jellyfin.resume", "play.circle"),
        ("jellyfin.library.inProgress.", "play.circle"),
        ("jellyfin.nextUp", "forward.end.circle"),
        ("jellyfin.library.nextUp.", "forward.end.circle"),
        ("jellyfin.latest.", "clock"),
        ("jellyfin.library.latestEpisodes.", "clock"),
        ("jellyfin.library.latestMovies.", "clock"),
        ("jellyfin.library.recommendation.", "hand.thumbsup"),
    ]

    private static func contentSystemImage(for items: [MediaDisplayItem]) -> String? {
        let kinds = Set(items.map(\.type))
        if kinds == [.movie] {
            return "film"
        }
        if !kinds.isEmpty, kinds.isSubset(of: [.series, .season, .episode]) {
            return "tv"
        }
        return nil
    }
}
