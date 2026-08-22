import Foundation

struct FavoriteScope: Codable, Hashable, Sendable {
    let provider: MediaProvider
    let serverID: String
    let profileID: String

    var storageKey: String {
        [provider.rawValue, serverID, profileID].joined(separator: "|")
    }

    static func plex(serverID: String, profileID: String) -> Self {
        Self(provider: .plex, serverID: serverID, profileID: profileID)
    }
}

struct PlexFavoriteSnapshot: Codable, Hashable, Identifiable, Sendable {
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
    let rating: Double?
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
    let grandparentTitle: String?
    let parentTitle: String?
    let parentIndex: Int?
    let index: Int?
    let grandparentThumbPath: String?
    let grandparentArtPath: String?
    let parentThumbPath: String?
    let libraryID: String?
    let libraryTitle: String?

    init(
        media: MediaItem,
        libraryID: String?,
        libraryTitle: String?,
    ) {
        id = media.id
        guid = media.guid
        summary = media.summary
        title = media.title
        type = media.type
        parentRatingKey = media.parentRatingKey
        grandparentRatingKey = media.grandparentRatingKey
        genres = media.genres
        year = media.year
        duration = media.duration
        rating = media.rating
        contentRating = media.contentRating
        studio = media.studio
        tagline = media.tagline
        thumbPath = media.thumbPath
        artPath = media.artPath
        artworkCornerColors = media.artworkCornerColors
        viewOffset = media.viewOffset
        viewCount = media.viewCount
        childCount = media.childCount
        leafCount = media.leafCount
        viewedLeafCount = media.viewedLeafCount
        grandparentTitle = media.grandparentTitle
        parentTitle = media.parentTitle
        parentIndex = media.parentIndex
        index = media.index
        grandparentThumbPath = media.grandparentThumbPath
        grandparentArtPath = media.grandparentArtPath
        parentThumbPath = media.parentThumbPath
        self.libraryID = libraryID
        self.libraryTitle = libraryTitle
    }

    init(plexItem: PlexItem, server: ServerIdentity) {
        let media = MediaItem(plexItem: plexItem, server: server)
        self.init(
            media: media,
            libraryID: plexItem.librarySectionID.map(String.init),
            libraryTitle: plexItem.librarySectionTitle,
        )
    }

    func media(serverID: String) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(
                server: ServerIdentity(provider: .plex, id: serverID),
                itemID: id,
            ),
            guid: guid,
            summary: summary,
            title: title,
            type: type,
            parentRatingKey: parentRatingKey,
            grandparentRatingKey: grandparentRatingKey,
            genres: genres,
            year: year,
            duration: duration,
            videoResolution: nil,
            rating: rating,
            ratings: [],
            contentRating: contentRating,
            studio: studio,
            tagline: tagline,
            thumbPath: thumbPath,
            artPath: artPath,
            artworkCornerColors: artworkCornerColors,
            viewOffset: viewOffset,
            viewCount: viewCount,
            childCount: childCount,
            leafCount: leafCount,
            viewedLeafCount: viewedLeafCount,
            watchState: MediaWatchState(
                isPlayed: (viewCount ?? 0) > 0,
                playCount: viewCount ?? 0,
                resumePosition: viewOffset,
                unplayedItemCount: nil,
                isFavorite: true,
            ),
            grandparentTitle: grandparentTitle,
            parentTitle: parentTitle,
            parentIndex: parentIndex,
            index: index,
            grandparentThumbPath: grandparentThumbPath,
            grandparentArtPath: grandparentArtPath,
            parentThumbPath: parentThumbPath,
        )
    }
}
