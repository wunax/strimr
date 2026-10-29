import Foundation

struct MediaItem: Identifiable, Hashable, Codable {
    let id: String
    let identity: MediaIdentity
    let guid: String
    let summary: String?
    let title: String
    /// Plex edition, e.g. `Director's Cut`. Each edition is its own item.
    let editionTitle: String?
    let type: MediaKind
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let genres: [String]
    let year: Int?
    let releaseDate: Date?
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
    let librarySectionID: String?
    let lastViewedAt: Date?
    /// Theme music of the item or of its series.
    let themePath: String?
    /// Title artwork drawn in place of the title text.
    let logoPath: String?
    /// Logo of the series, for episodes and seasons.
    let grandparentLogoPath: String?
    /// Optional so items persisted before external ids existed still decode.
    private let storedExternalIDs: ExternalIDs?

    var externalIDs: ExternalIDs {
        storedExternalIDs ?? ExternalIDs()
    }

    var provider: MediaProvider {
        identity.server.provider
    }

    var serverIdentifier: String {
        identity.server.id
    }

    init(
        id: String,
        identity: MediaIdentity? = nil,
        guid: String,
        summary: String?,
        title: String,
        editionTitle: String? = nil,
        type: MediaKind,
        parentRatingKey: String?,
        grandparentRatingKey: String?,
        genres: [String],
        year: Int?,
        releaseDate: Date? = nil,
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
        parentThumbPath: String?,
        librarySectionID: String? = nil,
        lastViewedAt: Date? = nil,
        externalIDs: ExternalIDs = ExternalIDs(),
        themePath: String? = nil,
        logoPath: String? = nil,
        grandparentLogoPath: String? = nil,
    ) {
        self.id = id
        self.identity = identity ?? Self.legacyIdentity(id: id, guid: guid)
        self.guid = guid
        self.summary = summary
        self.title = title
        let editionTitle = editionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.editionTitle = editionTitle?.isEmpty == false ? editionTitle : nil
        self.type = type
        self.parentRatingKey = parentRatingKey
        self.grandparentRatingKey = grandparentRatingKey
        self.genres = genres
        self.year = year
        self.releaseDate = releaseDate
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
        self.librarySectionID = librarySectionID
        self.lastViewedAt = lastViewedAt
        self.themePath = themePath
        self.logoPath = logoPath
        self.grandparentLogoPath = grandparentLogoPath
        storedExternalIDs = externalIDs.isEmpty ? nil : externalIDs
    }

    private static func legacyIdentity(id: String, guid: String) -> MediaIdentity {
        let isJellyfin = guid.hasPrefix("jellyfin://")
        let serverID = isJellyfin
            ? guid.split(separator: "/").dropFirst(2).first.map(String.init) ?? "jellyfin"
            : "plex"
        return MediaIdentity(
            server: ServerIdentity(provider: isJellyfin ? .jellyfin : .plex, id: serverID),
            itemID: id,
        )
    }

    var kind: MediaKind {
        type
    }

    var matchDescriptor: MediaMatchDescriptor {
        let kind: MediaMatchDescriptor.Kind = switch type {
        case .movie: .movie
        case .series: .series
        case .season: .season
        case .episode: .episode
        case .clip, .collection, .playlist, .folder, .unknown: .other
        }
        return MediaMatchDescriptor(
            kind: kind,
            guid: guid,
            externalIDs: externalIDs,
            seasonNumber: type == .episode ? parentIndex : nil,
            episodeNumber: type == .episode ? index : nil,
            edition: editionTitle,
        )
    }

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
        case .movie, .episode, .clip:
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

    /// Only modern-agent guids (`plex://movie/<id>`) map to a Plex Discover ID; legacy agent and local guids do not.
    var plexGuidID: String? {
        guard guid.hasPrefix("plex://") else { return nil }
        return guid.split(separator: "/").last.map(String.init)
    }

    var preferredThumbPath: String? {
        grandparentThumbPath ?? parentThumbPath ?? thumbPath
    }

    /// The series logo stands for its episodes and seasons, which have none of their own.
    var preferredLogoPath: String? {
        switch type {
        case .episode, .season:
            grandparentLogoPath
        default:
            logoPath
        }
    }

    var preferredArtPath: String? {
        if type == .episode {
            return thumbPath ?? grandparentArtPath ?? artPath
        }

        if type == .clip {
            return thumbPath ?? artPath
        }

        return grandparentArtPath ?? artPath
    }

    var secondaryLabel: String? {
        switch type {
        case .movie:
            return withEdition(year.map(String.init))

        case .series:
            switch provider {
            case .jellyfin:
                return year.map(String.init)
            case .plex:
                return withEdition(childCount.map { String(localized: "media.labels.seasonsCount \($0)") })
            }

        case .season, .episode:
            return title

        case .collection:
            guard let childCount else { return nil }
            return String(localized: "media.labels.elementsCount \(childCount)")

        case .clip, .playlist, .folder, .unknown:
            return nil
        }
    }

    /// Plex leaves the edition empty on the regular cut.
    var editionLabel: String {
        editionTitle ?? String(localized: "media.editions.standard")
    }

    /// The regular cut first, then editions by name.
    static func editionOrder(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        switch (lhs.editionTitle, rhs.editionTitle) {
        case (nil, nil): lhs.id < rhs.id
        case (nil, _): true
        case (_, nil): false
        case let (lhs?, rhs?): lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    /// Editions of a title share its poster and name, so cards tell them apart by the edition.
    private func withEdition(_ label: String?) -> String? {
        let parts = [label, editionTitle].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var tertiaryLabel: String? {
        guard case .episode = type, let parentIndex, let index else {
            return nil
        }

        return String(localized: "media.labels.seasonEpisode \(parentIndex) \(index)")
    }

    var episodeTitleLabel: String? {
        guard case .episode = type else { return nil }

        let episodeTitle = title.trimmingCharacters(in: .whitespaces)
        guard let tertiaryLabel else {
            return episodeTitle.isEmpty ? nil : episodeTitle
        }
        guard !episodeTitle.isEmpty else { return tertiaryLabel }

        return String(localized: "media.labels.episodeWithTitle \(tertiaryLabel) \(episodeTitle)")
    }

    var metadataRatingKey: String {
        switch type {
        case .episode:
            grandparentRatingKey ?? parentRatingKey ?? id
        case .season:
            parentRatingKey ?? id
        case .movie, .series, .clip:
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
