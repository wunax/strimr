import Foundation

extension MediaItem {
    init(plexItem: PlexItem) {
        self.init(
            id: plexItem.ratingKey,
            guid: plexItem.guid,
            summary: plexItem.summary,
            title: plexItem.title,
            type: plexItem.type,
            parentRatingKey: plexItem.parentRatingKey,
            grandparentRatingKey: plexItem.grandparentRatingKey,
            genres: plexItem.genres?.map(\.tag) ?? [],
            year: plexItem.year,
            duration: plexItem.duration.map { TimeInterval($0) / 1000 },
            videoResolution: plexItem.media?.first?.videoResolution,
            rating: plexItem.rating ?? plexItem.audienceRating,
            contentRating: plexItem.contentRating,
            studio: plexItem.studio,
            tagline: plexItem.tagline,
            thumbPath: plexItem.thumb,
            artPath: plexItem.art ?? plexItem.thumb,
            ultraBlurColors: plexItem.ultraBlurColors,
            viewOffset: plexItem.viewOffset.map { TimeInterval($0) / 1000 },
            viewCount: plexItem.viewCount,
            childCount: plexItem.childCount,
            leafCount: plexItem.leafCount,
            viewedLeafCount: plexItem.viewedLeafCount,
            grandparentTitle: plexItem.grandparentTitle,
            parentTitle: plexItem.parentTitle,
            parentIndex: plexItem.parentIndex,
            index: plexItem.index,
            grandparentThumbPath: plexItem.grandparentThumb,
            grandparentArtPath: plexItem.grandparentArt,
            parentThumbPath: plexItem.parentThumb,
        )
    }
}
