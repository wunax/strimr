import Foundation

struct CollectionMediaItem: Identifiable, Hashable, Codable {
    let id: String
    let key: String
    let guid: String
    let type: MediaKind
    let title: String
    let summary: String?
    let thumbPath: String?
    let childCount: Int?
    let minYear: String?
    let maxYear: String?
    private(set) var server: ServerIdentity = .unassigned

    init(
        id: String,
        key: String,
        guid: String,
        type: MediaKind,
        title: String,
        summary: String?,
        thumbPath: String?,
        childCount: Int?,
        minYear: String?,
        maxYear: String?,
        server: ServerIdentity,
    ) {
        self.id = id
        self.key = key
        self.guid = guid
        self.type = type
        self.title = title
        self.summary = summary
        self.thumbPath = thumbPath
        self.childCount = childCount
        self.minYear = minYear
        self.maxYear = maxYear
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
        thumbPath = try container.decodeIfPresent(String.self, forKey: .thumbPath)
        childCount = try container.decodeIfPresent(Int.self, forKey: .childCount)
        minYear = try container.decodeIfPresent(String.self, forKey: .minYear)
        maxYear = try container.decodeIfPresent(String.self, forKey: .maxYear)
        server = try container.decodeIfPresent(ServerIdentity.self, forKey: .server) ?? .unassigned
    }

    func assigning(server: ServerIdentity) -> CollectionMediaItem {
        var item = self
        item.server = server
        return item
    }
}

extension CollectionMediaItem {
    init(plexItem: PlexItem, server: ServerIdentity) {
        self.init(
            id: plexItem.ratingKey,
            key: plexItem.key,
            guid: plexItem.guid,
            type: plexItem.type.mediaKind,
            title: plexItem.title,
            summary: plexItem.summary,
            thumbPath: plexItem.thumb,
            childCount: plexItem.childCount,
            minYear: plexItem.minYear,
            maxYear: plexItem.maxYear,
            server: server,
        )
    }
}
