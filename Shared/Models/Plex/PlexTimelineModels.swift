import Foundation

struct PlexTimelineResponse: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let playbackState: String?
        let terminationCode: Int?
        let terminationText: String?
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}
