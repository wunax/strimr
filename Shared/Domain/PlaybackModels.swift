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
    let isExternal: Bool
    let title: String
    let language: String?
    let codec: String?
    let isDefault: Bool
    let isForced: Bool
    let isHearingImpaired: Bool
}

struct MediaTrackMetadata: Sendable, Hashable, Identifiable {
    let id: Int?
    let sourceIndex: Int?
    let codec: String
    let title: String?
    let displayTitle: String
    let language: String?
    let isDefault: Bool
    let isForced: Bool
    let isHearingImpaired: Bool
}

struct MediaChapter: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let index: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let image: ArtworkReference?
    let thumbPath: String?

    var stableID: String {
        id
    }

    var isValid: Bool {
        startTime >= 0 && endTime > startTime
    }

    func contains(time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}

struct SkipSegment: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable, Hashable {
        case intro
        case credits
    }

    let id: String
    let kind: Kind
    let startTime: TimeInterval
    let endTime: TimeInterval

    var isIntro: Bool {
        kind == .intro
    }

    var isCredits: Bool {
        kind == .credits
    }

    func contains(time: TimeInterval) -> Bool {
        time >= startTime && time <= endTime
    }
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
    let skipSegments: [SkipSegment]
    let scrubThumbnailSource: ScrubThumbnailSource?
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
