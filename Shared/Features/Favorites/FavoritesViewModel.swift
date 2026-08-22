import Foundation
import Observation

enum FavoriteCategory: String, CaseIterable, Hashable, Identifiable {
    case movies
    case shows
    case seasons
    case episodes

    var id: Self { self }

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

@MainActor
@Observable
final class FavoritesViewModel {
    @ObservationIgnored private let service: any MediaFavoritesService

    private(set) var itemsByCategory: [FavoriteCategory: [MediaDisplayItem]] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(services: MediaServices) {
        service = services.favorites
    }

    func items(for category: FavoriteCategory) -> [MediaDisplayItem] {
        itemsByCategory[category, default: []]
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let media = try await service.favorites()
            var grouped = Dictionary(uniqueKeysWithValues: FavoriteCategory.allCases.map { ($0, [MediaDisplayItem]()) })
            for item in media {
                guard let category = FavoriteCategory.allCases.first(where: { $0.mediaKind == item.type }),
                      let displayItem = MediaDisplayItem.playable(item) as MediaDisplayItem?
                else { continue }
                grouped[category, default: []].append(displayItem)
            }
            for category in FavoriteCategory.allCases {
                grouped[category]?.sort {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
            }
            guard !Task.isCancelled else { return }
            itemsByCategory = grouped
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
            ErrorReporter.capture(error)
        }
    }
}
