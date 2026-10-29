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
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        seriesTitle: String? = nil,
        librarySectionID: String? = nil,
        lastViewedAt: Date? = nil,
        viewOffset: TimeInterval? = nil,
        viewCount: Int? = nil,
    ) -> MediaItem {
        MediaItem(
            id: id,
            identity: MediaIdentity(server: server, itemID: id),
            guid: guid,
            summary: nil,
            title: title,
            editionTitle: editionTitle,
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: [],
            year: year,
            duration: nil,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: nil,
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
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
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
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
