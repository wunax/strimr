import AetherEngine
import Foundation

enum PlaybackMethod: String, Sendable {
    case directPlay
    case transcode
    case offline
}

enum TranscodeQualityPreset: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case original
    case p240_320
    case p360_700
    case p480_1_5mbps
    case p720_2mbps
    case p720_4mbps
    case p1080_8mbps
    case p1080_12mbps

    var id: String { rawValue }

    var isOriginal: Bool { self == .original }

    var maximumVideoBitrateKbps: Int? {
        switch self {
        case .original: nil
        case .p240_320: 320
        case .p360_700: 700
        case .p480_1_5mbps: 1_500
        case .p720_2mbps: 2_000
        case .p720_4mbps: 4_000
        case .p1080_8mbps: 8_000
        case .p1080_12mbps: 12_000
        }
    }

    var maximumHeight: Int? {
        switch self {
        case .original: nil
        case .p240_320: 240
        case .p360_700: 360
        case .p480_1_5mbps: 480
        case .p720_2mbps, .p720_4mbps: 720
        case .p1080_8mbps, .p1080_12mbps: 1_080
        }
    }

    var maximumWidth: Int? {
        switch self {
        case .original: nil
        case .p240_320: 426
        case .p360_700: 640
        case .p480_1_5mbps: 854
        case .p720_2mbps, .p720_4mbps: 1_280
        case .p1080_8mbps, .p1080_12mbps: 1_920
        }
    }

    var title: String {
        guard let bitrate = maximumVideoBitrateKbps,
              let height = maximumHeight
        else { return String(localized: "quality.original") }
        if bitrate < 1_000 {
            return String(localized: "quality.preset.kbps \(String(height)) \(String(bitrate))")
        }
        let bitrateText = bitrate == 1_500 ? "1.5" : String(bitrate / 1_000)
        return String(localized: "quality.preset.mbps \(String(height)) \(bitrateText)")
    }

    static let displayOrder: [TranscodeQualityPreset] = [
        .original,
        .p1080_12mbps,
        .p1080_8mbps,
        .p720_4mbps,
        .p720_2mbps,
        .p480_1_5mbps,
        .p360_700,
        .p240_320,
    ]

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
    let requestedQuality: TranscodeQualityPreset
    let effectiveQuality: TranscodeQualityPreset
    let qualityFallbackMessage: String?
    let mediaSourceID: String?
    let playSessionID: String?
    let transcodeSessionID: String?
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
