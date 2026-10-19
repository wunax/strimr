import Foundation

nonisolated struct PlexPlayQueueResponse: Codable, Equatable {
    let mediaContainer: MediaContainer

    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let identifier: String?
        let mediaTagPrefix: String?
        let mediaTagVersion: Int?
        let playQueueID: Int
        let playQueueSelectedItemID: Int?
        let playQueueSelectedItemOffset: Int?
        let playQueueSelectedMetadataItemID: String?
        let playQueueShuffled: Bool?
        let playQueueSourceURI: String?
        let playQueueTotalCount: Int?
        let playQueueVersion: Int?
        let metadata: [PlexItem]?

        private enum CodingKeys: String, CodingKey {
            case size
            case identifier
            case mediaTagPrefix
            case mediaTagVersion
            case playQueueID
            case playQueueSelectedItemID
            case playQueueSelectedItemOffset
            case playQueueSelectedMetadataItemID
            case playQueueShuffled
            case playQueueSourceURI
            case playQueueTotalCount
            case playQueueVersion
            case metadata = "Metadata"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

nonisolated extension PlexPlayQueueResponse.MediaContainer {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        mediaTagPrefix = try container.decodeIfPresent(String.self, forKey: .mediaTagPrefix)
        mediaTagVersion = try container.decodeIfPresent(Int.self, forKey: .mediaTagVersion)
        playQueueID = try container.decode(Int.self, forKey: .playQueueID)
        playQueueSelectedItemID = try container.decodeIfPresent(Int.self, forKey: .playQueueSelectedItemID)
        playQueueSelectedItemOffset = try container.decodeIfPresent(Int.self, forKey: .playQueueSelectedItemOffset)
        playQueueSelectedMetadataItemID = try container.decodeIfPresent(
            String.self,
            forKey: .playQueueSelectedMetadataItemID,
        )
        playQueueShuffled = try container.decodeIfPresent(Bool.self, forKey: .playQueueShuffled)
        playQueueSourceURI = try container.decodeIfPresent(String.self, forKey: .playQueueSourceURI)
        playQueueTotalCount = try container.decodeIfPresent(Int.self, forKey: .playQueueTotalCount)
        playQueueVersion = try container.decodeIfPresent(Int.self, forKey: .playQueueVersion)
        metadata = try container.decodeLossyArrayIfPresent(PlexItem.self, forKey: .metadata)
    }
}
