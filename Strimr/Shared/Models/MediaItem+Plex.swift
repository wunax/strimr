import Foundation

extension MediaItem {
    init(plexItem: PlexItem) {
        let resolvedId = UUID(uuidString: plexItem.ratingKey) ?? UUID()
        let subtitle = MediaItem.subtitle(for: plexItem)
        let genres = plexItem.genres?.map { $0.tag } ?? []
        let durationSeconds = plexItem.duration.map { TimeInterval(Double($0) / 1000) }

        self.init(
            id: resolvedId,
            title: plexItem.title,
            subtitle: subtitle,
            genres: genres,
            year: plexItem.year,
            duration: durationSeconds,
            rating: plexItem.rating
        )
    }

    private static func subtitle(for item: PlexItem) -> String {
        if let grandparentTitle = item.grandparentTitle {
            if let parentTitle = item.parentTitle {
                return "\(grandparentTitle) • \(parentTitle)"
            }
            return grandparentTitle
        }
        if let parentTitle = item.parentTitle {
            return parentTitle
        }
        if let tagline = item.tagline {
            return tagline
        }
        if let summary = item.summary {
            return summary
        }
        return ""
    }
}
