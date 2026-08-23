import Foundation

@MainActor
enum LiveTVErrorReporting {
    static func capture(_ error: Error) {
        guard !error.isCancellation else { return }
        let error = error as NSError
        ErrorReporter.capture(SanitizedLiveTVError(domain: error.domain, code: error.code))
    }
}

private struct SanitizedLiveTVError: LocalizedError {
    let domain: String
    let code: Int

    var errorDescription: String? {
        "Live TV operation failed (\(domain), code \(code))."
    }
}

struct LiveTVChannel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let callSign: String?
    let number: String?
    let thumbPath: String?
    let artPath: String?
    let lineupID: String?
    let dvrID: String?
    let isHD: Bool
    var isFavorite: Bool

    var displayTitle: String {
        let name = callSign?.nilIfEmpty ?? title
        guard let number = number?.nilIfEmpty else { return name }
        return "\(number) · \(name)"
    }
}

struct LiveTVProgram: Identifiable, Hashable, Sendable {
    let id: String
    let channelID: String
    let title: String
    let seriesTitle: String?
    let summary: String?
    let startDate: Date
    let endDate: Date
    let thumbPath: String?
    let artPath: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let isLive: Bool
    let isPremiere: Bool
    let recordingID: String?
    let seriesRecordingID: String?
    let providerGUID: String?

    var isCurrentlyAiring: Bool {
        let now = Date()
        return startDate <= now && now < endDate
    }

    var progress: Double {
        let duration = endDate.timeIntervalSince(startDate)
        guard duration > 0 else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(startDate) / duration))
    }
}

struct LiveTVOnNowSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let programs: [LiveTVProgram]
}

struct LiveTVCaptureRange: Hashable, Sendable {
    let startDate: Date
    let endDate: Date

    var duration: TimeInterval { max(0, endDate.timeIntervalSince(startDate)) }
}

enum LiveTVBackgroundPolicy: Equatable, Sendable {
    case retainSession
    case stopAndExit
}

struct LiveTVPlaybackSource: Sendable {
    let url: URL
    let httpHeaders: [String: String]
    let program: LiveTVProgram?
    let captureRange: LiveTVCaptureRange?
    let nativeRemoteHLS: Bool
}

struct LiveTVLaunchContext: Sendable {
    let channels: [LiveTVChannel]
    let selectedIndex: Int
    let program: LiveTVProgram?
    let startsFromBeginning: Bool

    init(
        channels: [LiveTVChannel],
        selectedIndex: Int,
        program: LiveTVProgram? = nil,
        startsFromBeginning: Bool = false
    ) {
        self.channels = channels
        self.selectedIndex = selectedIndex
        self.program = program
        self.startsFromBeginning = startsFromBeginning
    }

    var channel: LiveTVChannel { channels[selectedIndex] }
}

enum DVRRecordingStatus: String, Codable, Hashable, Sendable {
    case scheduled
    case recording
    case completed
    case cancelled
    case error
    case unknown
}

struct DVRRecording: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let channelTitle: String?
    let startDate: Date?
    let endDate: Date?
    let status: DVRRecordingStatus
    let programID: String?
    let playableMedia: MediaItem?
    let errorMessage: String?
}

struct DVRRecordingRule: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let isSeries: Bool
    let targetLibraryID: String?
    let targetLibraryTitle: String?
    let optionValues: [String: String]
}

enum DVRRecordingOptionKind: Hashable, Sendable {
    case toggle
    case choice([DVRRecordingOptionChoice])
    case integer
    case text
}

struct DVRRecordingOptionChoice: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
}

struct DVRRecordingOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String?
    let kind: DVRRecordingOptionKind
    let defaultValue: String
}

struct DVRRecordingTemplate: Hashable, Sendable {
    let programID: String
    let supportsSingle: Bool
    let supportsSeries: Bool
    let libraries: [Library]
    let defaultLibraryID: String?
    let options: [DVRRecordingOption]
}

struct DVRRecordingRequest: Sendable {
    let program: LiveTVProgram
    let recordsSeries: Bool
    let targetLibraryID: String?
    let options: [String: String]
}

extension String {
    fileprivate var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
