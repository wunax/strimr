import Foundation

struct PlaylistMediaItem: Identifiable, Hashable, Codable {
    let id: String
    let key: String
    let guid: String
    let type: MediaKind
    let title: String
    let summary: String?
    let compositePath: String?
    let duration: Int?
    let leafCount: Int?
    let playlistType: String?
    private(set) var server: ServerIdentity = .unassigned

    init(
        id: String,
        key: String,
        guid: String,
        type: MediaKind,
        title: String,
        summary: String?,
        compositePath: String?,
        duration: Int?,
        leafCount: Int?,
        playlistType: String?,
        server: ServerIdentity,
    ) {
        self.id = id
        self.key = key
        self.guid = guid
        self.type = type
        self.title = title
        self.summary = summary
        self.compositePath = compositePath
        self.duration = duration
        self.leafCount = leafCount
        self.playlistType = playlistType
        self.server = server
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        key = try container.decode(String.self, forKey: .key)
        guid = try container.decode(String.self, forKey: .guid)
        type = try container.decode(MediaKind.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        compositePath = try container.decodeIfPresent(String.self, forKey: .compositePath)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        leafCount = try container.decodeIfPresent(Int.self, forKey: .leafCount)
        playlistType = try container.decodeIfPresent(String.self, forKey: .playlistType)
        server = try container.decodeIfPresent(ServerIdentity.self, forKey: .server) ?? .unassigned
    }

    func assigning(server: ServerIdentity) -> PlaylistMediaItem {
        var item = self
        item.server = server
        return item
    }
}

extension PlaylistMediaItem {
    init(plexItem: PlexItem, server: ServerIdentity) {
        self.init(
            id: plexItem.ratingKey,
            key: plexItem.key,
            guid: plexItem.guid,
            type: plexItem.type.mediaKind,
            title: plexItem.title,
            summary: plexItem.summary,
            compositePath: plexItem.composite,
            duration: plexItem.duration,
            leafCount: plexItem.leafCount,
            playlistType: plexItem.playlistType,
            server: server,
        )
    }
}
