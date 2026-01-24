import Foundation

struct CollectionMediaItem: Identifiable, Hashable {
    let id: String
    let key: String
    let guid: String
    let type: PlexItemType
    let title: String
    let summary: String?
    let thumbPath: String?
    let childCount: Int?
    let minYear: String?
    let maxYear: String?
}

extension CollectionMediaItem {
    init(plexItem: PlexItem) {
        self.init(
            id: plexItem.ratingKey,
            key: plexItem.key,
            guid: plexItem.guid,
            type: plexItem.type,
            title: plexItem.title,
            summary: plexItem.summary,
            thumbPath: plexItem.thumb,
            childCount: plexItem.childCount,
            minYear: plexItem.minYear,
            maxYear: plexItem.maxYear,
        )
    }
}
