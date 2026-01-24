import Foundation

struct PlexPlayQueueResponse: Codable, Equatable {
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
