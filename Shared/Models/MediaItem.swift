import Foundation

struct MediaItem: Identifiable, Hashable {
    let id: String
    let guid: String
    let summary: String?
    let title: String
    let type: PlexItemType
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let genres: [String]
    let year: Int?
    let duration: TimeInterval?
    let rating: Double?
    let contentRating: String?
    let studio: String?
    let tagline: String?
    let thumbPath: String?
    let artPath: String?
    let ultraBlurColors: PlexUltraBlurColors?
    let viewOffset: TimeInterval?
    let viewCount: Int?
    let childCount: Int?
    let leafCount: Int?
    let viewedLeafCount: Int?
    let grandparentTitle: String?
    let parentTitle: String?
    let parentIndex: Int?
    let index: Int?
    let grandparentThumbPath: String?
    let grandparentArtPath: String?
    let parentThumbPath: String?

    var primaryLabel: String {
        grandparentTitle ?? parentTitle ?? title
    }

    var plexGuidID: String? {
        guid.split(separator: "/").last.map(String.init)
    }

    var preferredThumbPath: String? {
        grandparentThumbPath ?? parentThumbPath ?? thumbPath
    }

    var preferredArtPath: String? {
        grandparentArtPath ?? artPath
    }

    var secondaryLabel: String? {
        switch type {
        case .movie:
            return year.map(String.init)

        case .show:
            guard let childCount else { return nil }
            return String(localized: "media.labels.seasonsCount \(childCount)")

        case .season, .episode:
            return title

        case .unknown, .collection:
            return nil
        }
    }

    var tertiaryLabel: String? {
        guard case .episode = type, let parentIndex, let index else {
            return nil
        }

        return String(localized: "media.labels.seasonEpisode \(parentIndex) \(index)")
    }

    var metadataRatingKey: String {
        switch type {
        case .episode:
            grandparentRatingKey ?? parentRatingKey ?? id
        case .season:
            parentRatingKey ?? id
        case .movie, .show:
            id
        case .unknown, .collection:
            id
        }
    }

    var viewProgressPercentage: Double? {
        guard let viewOffset, let duration, duration > 0 else {
            return nil
        }

        return min(100, (viewOffset / duration) * 100)
    }
}
