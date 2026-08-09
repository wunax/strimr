import AetherEngine
import Foundation

enum PlaybackMethod: String, Sendable {
    case directPlay
    case offline
}

enum PlaybackTrackKind: String, Sendable {
    case audio
    case subtitle
}

struct PlaybackTrack: Sendable, Hashable, Identifiable {
    let id: String
    let sourceIndex: Int
    let kind: PlaybackTrackKind
    let title: String
    let language: String?
    let codec: String?
    let isDefault: Bool
    let isForced: Bool
    let isHearingImpaired: Bool
}

struct MediaChapter: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let startTime: TimeInterval
    let image: ArtworkReference?
}

struct PlaybackPlan: Sendable {
    let media: MediaItem
    let url: URL
    let httpHeaders: [String: String]
    let method: PlaybackMethod
    let mediaSourceID: String?
    let playSessionID: String?
    let initialPosition: TimeInterval?
    let selectedAudioIndex: Int?
    let selectedSubtitleIndex: Int?
    let tracks: [PlaybackTrack]
    let externalSubtitles: [ExternalSubtitleTrack]
    let chapters: [MediaChapter]
}

struct PlaybackQueueItem: Sendable, Equatable, Identifiable {
    let id: UUID
    let media: MediaItem
    let providerQueueItemID: String?
}

struct PlaybackQueue: Sendable, Equatable {
    let id: UUID
    var items: [PlaybackQueueItem]
    var currentIndex: Int
    var isShuffled: Bool
}
