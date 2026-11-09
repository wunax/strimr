import Foundation
@testable import Strimr

extension MediaItem {
    static func make(
        id: String,
        server: ServerIdentity,
        title: String = "Title",
        editionTitle: String? = nil,
        type: MediaKind = .movie,
        guid: String = "",
        externalIDs: ExternalIDs = ExternalIDs(),
        year: Int? = nil,
        videoResolution: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        seriesTitle: String? = nil,
        parentID: String? = nil,
        seriesID: String? = nil,
        librarySectionID: String? = nil,
        lastViewedAt: Date? = nil,
        viewOffset: TimeInterval? = nil,
        viewCount: Int? = nil,
        thumbPath: String? = nil,
        artPath: String? = nil,
        grandparentThumbPath: String? = nil,
        grandparentArtPath: String? = nil,
        parentThumbPath: String? = nil,
    ) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(server: server, itemID: id),
            guid: guid,
            summary: nil,
            title: title,
            editionTitle: editionTitle,
            type: type,
            parentRatingKey: parentID,
            grandparentRatingKey: seriesID,
            genres: [],
            year: year,
            duration: nil,
            videoResolution: videoResolution,
            rating: nil,
            ratings: [],
            contentRating: nil,
            studio: nil,
            tagline: nil,
            thumbPath: thumbPath,
            artPath: artPath,
            artworkCornerColors: nil,
            viewOffset: viewOffset,
            viewCount: viewCount,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: seriesTitle,
            parentTitle: nil,
            parentIndex: seasonNumber,
            index: episodeNumber,
            grandparentThumbPath: grandparentThumbPath,
            grandparentArtPath: grandparentArtPath,
            parentThumbPath: parentThumbPath,
            librarySectionID: librarySectionID,
            lastViewedAt: lastViewedAt,
            externalIDs: externalIDs,
        )
    }
}

extension Hub {
    static func make(id: String, key: String = "", title: String, items: [MediaItem], server: ServerIdentity?) -> Hub {
        Hub(
            id: id,
            key: key,
            hubKey: nil,
            title: title,
            size: items.count,
            more: false,
            items: items.map(MediaDisplayItem.playable),
            server: server,
        )
    }
}
