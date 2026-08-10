import Foundation

extension MediaItem {
    init(plexItem: PlexItem, server: ServerIdentity? = nil) {
        let isPlayed = switch plexItem.type.mediaKind {
        case .movie, .episode:
            (plexItem.viewCount ?? 0) > 0
        case .series, .season:
            if let leafCount = plexItem.leafCount,
               let viewedLeafCount = plexItem.viewedLeafCount,
               leafCount > 0
            {
                leafCount == viewedLeafCount
            } else {
                false
            }
        case .collection, .playlist, .folder, .unknown:
            false
        }
        let unplayedItemCount: Int? = if let leafCount = plexItem.leafCount,
                                         let viewedLeafCount = plexItem.viewedLeafCount
        {
            max(0, leafCount - viewedLeafCount)
        } else {
            nil
        }

        self.init(
            id: plexItem.ratingKey,
            identity: MediaIdentity(
                server: server ?? ServerIdentity(provider: .plex, id: "plex"),
                itemID: plexItem.ratingKey
            ),
            guid: plexItem.guid,
            summary: plexItem.summary,
            title: plexItem.title,
            type: plexItem.type.mediaKind,
            parentRatingKey: plexItem.parentRatingKey,
            grandparentRatingKey: plexItem.grandparentRatingKey,
            genres: plexItem.genres?.map(\.tag) ?? [],
            year: plexItem.year,
            duration: plexItem.duration.map { TimeInterval($0) / 1000 },
            videoResolution: plexItem.media?.first?.videoResolution,
            rating: plexItem.rating ?? plexItem.audienceRating,
            ratings: plexItem.ratings?.compactMap {
                MediaRating(imageIdentifier: $0.image, value: $0.value)
            } ?? [],
            contentRating: plexItem.contentRating,
            studio: plexItem.studio,
            tagline: plexItem.tagline,
            thumbPath: plexItem.thumb,
            artPath: plexItem.art ?? plexItem.thumb,
            artworkCornerColors: plexItem.ultraBlurColors,
            viewOffset: plexItem.viewOffset.map { TimeInterval($0) / 1000 },
            viewCount: plexItem.viewCount,
            childCount: plexItem.childCount,
            leafCount: plexItem.leafCount,
            viewedLeafCount: plexItem.viewedLeafCount,
            watchState: MediaWatchState(
                isPlayed: isPlayed,
                playCount: plexItem.viewCount ?? 0,
                resumePosition: plexItem.viewOffset.map { TimeInterval($0) / 1000 },
                unplayedItemCount: unplayedItemCount,
                isFavorite: false
            ),
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
