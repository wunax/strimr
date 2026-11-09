import Foundation

/// One page of the home hero.
struct HomeHeroSlide: Identifiable, Hashable {
    enum Badge: Hashable {
        case featured(FeaturedReason, newSeasonNumber: Int?, collectionTitle: String?)
        case resume
    }

    let media: MediaItem
    let badge: Badge

    var id: MediaIdentity {
        media.identity
    }

    var isResume: Bool {
        badge == .resume
    }

    /// Small label above the title, saying why the title is there.
    var eyebrow: String? {
        switch badge {
        case let .featured(reason, newSeasonNumber, collectionTitle):
            switch reason {
            case .curated:
                collectionTitle
            case .recentlyAdded:
                String(localized: "home.featured.recentlyAdded")
            case .newSeason:
                newSeasonNumber.map { String(localized: "home.featured.newSeason \($0)") }
                    ?? String(localized: "home.featured.newEpisodes")
            case .trending:
                String(localized: "home.featured.trending")
            case .rediscover:
                String(localized: "home.featured.rediscover")
            }
        case .resume:
            media.tertiaryLabel
        }
    }

    var accessibilityLabel: String {
        [eyebrow, media.primaryLabel, media.year.map(String.init)].compactMap(\.self).joined(separator: ", ")
    }
}

enum HomeHeroSlides {
    static let resumeLimit = 10

    static func featured(_ candidates: [FeaturedCandidate]) -> [HomeHeroSlide] {
        candidates.map { candidate in
            HomeHeroSlide(
                media: candidate.item,
                badge: .featured(
                    candidate.reason,
                    newSeasonNumber: candidate.newSeasonNumber,
                    collectionTitle: candidate.collectionTitle,
                ),
            )
        }
    }

    /// The merged Continue Watching row, which already holds Next Up when the user merges them. A single item is
    /// enough for a hero.
    static func resume(from rows: [HomeRow]) -> [HomeHeroSlide] {
        guard let row = rows.first(where: { $0.kind == .continueWatching }) else { return [] }
        return row.items.compactMap(\.playableItem)
            .filter { $0.type == .movie || $0.type == .episode }
            .prefix(resumeLimit)
            .map { HomeHeroSlide(media: $0, badge: .resume) }
    }

    /// Items of the watching rows, which the featured hero never repeats.
    static func watchingItems(in rows: [HomeRow]) -> [MediaItem] {
        rows.filter(\.isWatchingRow).flatMap(\.items).compactMap(\.playableItem)
    }
}
