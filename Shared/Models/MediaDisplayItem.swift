import Foundation

enum MediaDisplayItem: Identifiable, Hashable {
    case playable(MediaItem)
    case collection(CollectionMediaItem)
    case playlist(PlaylistMediaItem)

    var id: String {
        switch self {
        case let .playable(item):
            item.id
        case let .collection(item):
            item.id
        case let .playlist(item):
            item.id
        }
    }

    var type: PlexItemType {
        switch self {
        case let .playable(item):
            item.type
        case let .collection(item):
            item.type
        case let .playlist(item):
            item.type
        }
    }

    var title: String {
        switch self {
        case let .playable(item):
            item.title
        case let .collection(item):
            item.title
        case let .playlist(item):
            item.title
        }
    }

    var summary: String? {
        switch self {
        case let .playable(item):
            item.summary
        case let .collection(item):
            item.summary
        case let .playlist(item):
            item.summary
        }
    }

    var thumbPath: String? {
        switch self {
        case let .playable(item):
            item.thumbPath
        case let .collection(item):
            item.thumbPath
        case let .playlist(item):
            item.compositePath
        }
    }

    var artPath: String? {
        switch self {
        case let .playable(item):
            item.artPath
        case .collection:
            nil
        case .playlist:
            nil
        }
    }

    var ultraBlurColors: PlexUltraBlurColors? {
        switch self {
        case let .playable(item):
            item.ultraBlurColors
        case .collection:
            nil
        case .playlist:
            nil
        }
    }

    var primaryLabel: String {
        switch self {
        case let .playable(item):
            item.primaryLabel
        case let .collection(item):
            item.title
        case let .playlist(item):
            item.title
        }
    }

    var secondaryLabel: String? {
        switch self {
        case let .playable(item):
            return item.secondaryLabel
        case let .collection(item):
            guard let childCount = item.childCount else { return nil }
            return String(localized: "media.labels.elementsCount \(childCount)")
        case let .playlist(item):
            guard let leafCount = item.leafCount else { return nil }
            return String(localized: "media.labels.elementsCount \(leafCount)")
        }
    }

    var tertiaryLabel: String? {
        switch self {
        case let .playable(item):
            item.tertiaryLabel
        case .collection:
            nil
        case .playlist:
            nil
        }
    }

    var preferredThumbPath: String? {
        switch self {
        case let .playable(item):
            item.preferredThumbPath
        case let .collection(item):
            item.thumbPath
        case let .playlist(item):
            item.compositePath
        }
    }

    var preferredArtPath: String? {
        switch self {
        case let .playable(item):
            item.preferredArtPath
        case .collection:
            nil
        case .playlist:
            nil
        }
    }

    var viewProgressPercentage: Double? {
        switch self {
        case let .playable(item):
            item.viewProgressPercentage
        case .collection:
            nil
        case .playlist:
            nil
        }
    }

    var remainingUnwatchedLeaves: Int? {
        switch self {
        case let .playable(item):
            item.remainingUnwatchedLeaves
        case .collection:
            nil
        case .playlist:
            nil
        }
    }

    var isFullyWatched: Bool {
        switch self {
        case let .playable(item):
            item.isFullyWatched
        case .collection:
            false
        case .playlist:
            false
        }
    }

    var playableItem: MediaItem? {
        switch self {
        case let .playable(item):
            item
        case .collection:
            nil
        case .playlist:
            nil
        }
    }
}

extension MediaDisplayItem {
    init?(plexItem: PlexItem) {
        switch plexItem.type {
        case .movie, .show, .season, .episode:
            self = .playable(MediaItem(plexItem: plexItem))
        case .collection:
            self = .collection(CollectionMediaItem(plexItem: plexItem))
        case .playlist:
            self = .playlist(PlaylistMediaItem(plexItem: plexItem))
        case .unknown:
            return nil
        }
    }
}
