import Foundation

struct PlaylistMediaItem: Identifiable, Hashable {
    let id: String
    let key: String
    let guid: String
    let type: PlexItemType
    let title: String
    let summary: String?
    let compositePath: String?
    let duration: Int?
    let leafCount: Int?
    let playlistType: String?
}

extension PlaylistMediaItem {
    init(plexItem: PlexItem) {
        self.init(
            id: plexItem.ratingKey,
            key: plexItem.key,
            guid: plexItem.guid,
            type: plexItem.type,
            title: plexItem.title,
            summary: plexItem.summary,
            compositePath: plexItem.composite,
            duration: plexItem.duration,
            leafCount: plexItem.leafCount,
            playlistType: plexItem.playlistType,
        )
    }
}
