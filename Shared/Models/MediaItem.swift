import Foundation

struct MediaItem: Identifiable, Hashable {
    let id: String
    let guid: String
    let summary: String?
    let title: String
    let type: MediaKind
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let genres: [String]
    let year: Int?
    let duration: TimeInterval?
    let videoResolution: String?
    let rating: Double?
    let ratings: [MediaRating]
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

    var identity: MediaIdentity {
        MediaIdentity(
            server: ServerIdentity(provider: provider, id: serverIdentifier),
            itemID: id,
        )
    }

    var provider: MediaProvider {
        guid.hasPrefix("jellyfin://") ? .jellyfin : .plex
    }

    var serverIdentifier: String {
        if provider == .jellyfin {
            return guid.split(separator: "/").dropFirst(2).first.map(String.init) ?? "jellyfin"
        }
        return "plex"
    }

    var kind: MediaKind { type }

    var hierarchy: MediaHierarchy {
        MediaHierarchy(
            parentID: parentRatingKey.map { MediaIdentity(server: identity.server, itemID: $0) },
            seriesID: grandparentRatingKey.map { MediaIdentity(server: identity.server, itemID: $0) },
            seasonID: parentRatingKey.map { MediaIdentity(server: identity.server, itemID: $0) },
            seriesTitle: grandparentTitle,
            seasonTitle: parentTitle,
            seasonNumber: parentIndex,
            episodeNumber: index,
        )
    }

    var watchState: MediaWatchState {
        MediaWatchState(
            isPlayed: (viewCount ?? 0) > 0,
            playCount: viewCount ?? 0,
            resumePosition: viewOffset,
            isFavorite: false,
        )
    }

    var counts: MediaCounts {
        MediaCounts(
            childCount: childCount,
            leafCount: leafCount,
            viewedLeafCount: viewedLeafCount,
        )
    }

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

        case .series:
            guard let childCount else { return nil }
            return String(localized: "media.labels.seasonsCount \(childCount)")

        case .season, .episode:
            return title

        case .collection:
            guard let childCount else { return nil }
            return String(localized: "media.labels.elementsCount \(childCount)")

        case .playlist, .folder, .unknown:
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
        case .movie, .series:
            id
        case .collection, .playlist, .folder, .unknown:
            id
        }
    }

    var viewProgressPercentage: Double? {
        guard let viewOffset, let duration, duration > 0 else {
            return nil
        }

        return min(100, (viewOffset / duration) * 100)
    }

    var playbackResolutionLabel: String? {
        guard var value = videoResolution?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        value = value.lowercased()

        if Int(value) != nil {
            return "\(value)p"
        }

        if value.hasSuffix("k") || value == "sd" || value == "uhd" {
            return value.uppercased()
        }

        return value
    }
}
