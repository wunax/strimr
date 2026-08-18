import Foundation

enum PlayableItemType: String, Codable, Hashable {
    case movie
    case show
    case season
    case episode

    init?(mediaKind: MediaKind) {
        switch mediaKind {
        case .movie:
            self = .movie
        case .series:
            self = .show
        case .season:
            self = .season
        case .episode:
            self = .episode
        case .collection, .playlist, .folder, .unknown:
            return nil
        }
    }

    var mediaKind: MediaKind {
        switch self {
        case .movie:
            .movie
        case .show:
            .series
        case .season:
            .season
        case .episode:
            .episode
        }
    }
}

struct PlayableMediaItem: Identifiable, Hashable {
    private let item: MediaItem
    let type: PlayableItemType

    init?(mediaItem: MediaItem) {
        guard let playableType = PlayableItemType(mediaKind: mediaItem.type) else { return nil }
        item = mediaItem
        type = playableType
    }

    init?(plexItem: PlexItem) {
        self.init(mediaItem: MediaItem(plexItem: plexItem))
    }

    var id: String {
        item.id
    }

    var title: String {
        item.title
    }

    var summary: String? {
        item.summary
    }

    var contentRating: String? {
        item.contentRating
    }

    var tagline: String? {
        item.tagline
    }

    var studio: String? {
        item.studio
    }

    var rating: Double? {
        item.rating
    }

    var ratings: [MediaRating] {
        item.ratings
    }

    var genres: [String] {
        item.genres
    }

    var year: Int? {
        item.year
    }

    var duration: TimeInterval? {
        item.duration
    }

    var thumbPath: String? {
        item.thumbPath
    }

    var parentThumbPath: String? {
        item.parentThumbPath
    }

    var grandparentThumbPath: String? {
        item.grandparentThumbPath
    }

    var artPath: String? {
        item.artPath
    }

    var primaryLabel: String {
        item.primaryLabel
    }

    var secondaryLabel: String? {
        item.secondaryLabel
    }

    var tertiaryLabel: String? {
        item.tertiaryLabel
    }

    var plexGuidID: String? {
        item.plexGuidID
    }

    var metadataRatingKey: String {
        item.metadataRatingKey
    }

    var viewOffset: TimeInterval? {
        item.viewOffset
    }

    var viewProgressPercentage: Double? {
        item.viewProgressPercentage
    }

    var mediaKind: MediaKind {
        type.mediaKind
    }

    var mediaItem: MediaItem {
        item
    }
}
