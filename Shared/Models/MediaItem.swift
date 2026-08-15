import Foundation

struct MediaItem: Identifiable, Hashable {
    let id: String
    let identity: MediaIdentity
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
    let artworkCornerColors: ArtworkCornerColors?
    let viewOffset: TimeInterval?
    let viewCount: Int?
    let childCount: Int?
    let leafCount: Int?
    let viewedLeafCount: Int?
    private let mappedWatchState: MediaWatchState?
    let grandparentTitle: String?
    let parentTitle: String?
    let parentIndex: Int?
    let index: Int?
    let grandparentThumbPath: String?
    let grandparentArtPath: String?
    let parentThumbPath: String?

    var provider: MediaProvider { identity.server.provider }
    var serverIdentifier: String { identity.server.id }

    init(
        id: String,
        identity: MediaIdentity? = nil,
        guid: String,
        summary: String?,
        title: String,
        type: MediaKind,
        parentRatingKey: String?,
        grandparentRatingKey: String?,
        genres: [String],
        year: Int?,
        duration: TimeInterval?,
        videoResolution: String?,
        rating: Double?,
        ratings: [MediaRating],
        contentRating: String?,
        studio: String?,
        tagline: String?,
        thumbPath: String?,
        artPath: String?,
        artworkCornerColors: ArtworkCornerColors?,
        viewOffset: TimeInterval?,
        viewCount: Int?,
        childCount: Int?,
        leafCount: Int?,
        viewedLeafCount: Int?,
        watchState: MediaWatchState? = nil,
        grandparentTitle: String?,
        parentTitle: String?,
        parentIndex: Int?,
        index: Int?,
        grandparentThumbPath: String?,
        grandparentArtPath: String?,
        parentThumbPath: String?
    ) {
        self.id = id
        self.identity = identity ?? Self.legacyIdentity(id: id, guid: guid)
        self.guid = guid
        self.summary = summary
        self.title = title
        self.type = type
        self.parentRatingKey = parentRatingKey
        self.grandparentRatingKey = grandparentRatingKey
        self.genres = genres
        self.year = year
        self.duration = duration
        self.videoResolution = videoResolution
        self.rating = rating
        self.ratings = ratings
        self.contentRating = contentRating
        self.studio = studio
        self.tagline = tagline
        self.thumbPath = thumbPath
        self.artPath = artPath
        self.artworkCornerColors = artworkCornerColors
        self.viewOffset = viewOffset
        self.viewCount = viewCount
        self.childCount = childCount
        self.leafCount = leafCount
        self.viewedLeafCount = viewedLeafCount
        mappedWatchState = watchState
        self.grandparentTitle = grandparentTitle
        self.parentTitle = parentTitle
        self.parentIndex = parentIndex
        self.index = index
        self.grandparentThumbPath = grandparentThumbPath
        self.grandparentArtPath = grandparentArtPath
        self.parentThumbPath = parentThumbPath
    }

    private static func legacyIdentity(id: String, guid: String) -> MediaIdentity {
        let isJellyfin = guid.hasPrefix("jellyfin://")
        let serverID = isJellyfin
            ? guid.split(separator: "/").dropFirst(2).first.map(String.init) ?? "jellyfin"
            : "plex"
        return MediaIdentity(
            server: ServerIdentity(provider: isJellyfin ? .jellyfin : .plex, id: serverID),
            itemID: id
        )
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
        if let mappedWatchState {
            return mappedWatchState
        }

        let isPlayed = switch kind {
        case .movie, .episode:
            (viewCount ?? 0) > 0
        case .series, .season:
            if let leafCount, let viewedLeafCount, leafCount > 0 {
                leafCount == viewedLeafCount
            } else {
                (viewCount ?? 0) > 0
            }
        case .collection, .playlist, .folder, .unknown:
            false
        }

        return MediaWatchState(
            isPlayed: isPlayed,
            playCount: viewCount ?? 0,
            resumePosition: viewOffset,
            unplayedItemCount: nil,
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
            switch provider {
            case .jellyfin:
                return year.map(String.init)
            case .plex:
                guard let childCount else { return nil }
                return String(localized: "media.labels.seasonsCount \(childCount)")
            }

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
