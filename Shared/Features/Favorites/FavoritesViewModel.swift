import Foundation
import Observation

enum FavoriteCategory: String, CaseIterable, Hashable, Identifiable {
    case movies
    case shows
    case seasons
    case episodes

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .movies:
            String(localized: "favorites.movies")
        case .shows:
            String(localized: "favorites.shows")
        case .seasons:
            String(localized: "favorites.seasons")
        case .episodes:
            String(localized: "favorites.episodes")
        }
    }

    var mediaKind: MediaKind {
        switch self {
        case .movies:
            .movie
        case .shows:
            .series
        case .seasons:
            .season
        case .episodes:
            .episode
        }
    }

    var layout: MediaCarousel.Layout {
        self == .episodes ? .landscape : .portrait
    }
}

/// Favorites of every enabled server of the profile, as one union.
@MainActor
@Observable
final class FavoritesViewModel {
    @ObservationIgnored private let sessionManager: SessionManager

    private(set) var itemsByCategory: [FavoriteCategory: [MediaDisplayItem]] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    func items(for category: FavoriteCategory) -> [MediaDisplayItem] {
        itemsByCategory[category, default: []]
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let result = await sessionManager.aggregation.fanOut(
            servers: sessionManager.registry.sessions,
            supports: \.capabilities.favorites,
        ) { services in
            try await services.favorites.favorites()
        }
        guard !Task.isCancelled else { return }
        let order = sessionManager.registry.sessions.map(\.identity)
        let media = order.flatMap { result.value[$0] ?? [] }
        var grouped = Dictionary(uniqueKeysWithValues: FavoriteCategory.allCases.map { ($0, [MediaDisplayItem]()) })
        for item in media {
            guard let category = FavoriteCategory.allCases.first(where: { $0.mediaKind == item.type }) else { continue }
            grouped[category, default: []].append(.playable(item))
        }
        for category in FavoriteCategory.allCases {
            grouped[category]?.sort {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
        itemsByCategory = grouped
        if media.isEmpty, result.succeeded.isEmpty, !result.failed.isEmpty {
            errorMessage = String(localized: "favorites.error.unavailable")
        }
    }
}
