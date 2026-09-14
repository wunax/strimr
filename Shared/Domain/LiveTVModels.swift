import Foundation

@MainActor
enum LiveTVErrorReporting {
    static func capture(_ error: Error) {
        guard !error.isCancellation else { return }
        ErrorReporter.capture(normalizedError(from: error))
    }

    private static func normalizedError(from error: Error) -> NSError {
        let underlying = error as NSError
        var userInfo: [String: Any] = [
            "underlying_domain": underlying.domain,
            "underlying_code": underlying.code,
        ]

        let provider: String
        let code: Int
        let statusCode: Int?

        switch error {
        case let error as PlexAPIError:
            provider = "plex"
            code = plexCode(for: error)
            statusCode = plexStatusCode(for: error)
        case let error as JellyfinAPIError:
            provider = "jellyfin"
            code = jellyfinCode(for: error)
            statusCode = jellyfinStatusCode(for: error)
        default:
            provider = "unknown"
            code = underlying.code
            statusCode = nil
        }

        userInfo["provider"] = provider
        if let statusCode {
            userInfo["http_status"] = statusCode
        }
        userInfo[NSLocalizedDescriptionKey] = "Live TV operation failed (\(provider), code \(code))."

        return NSError(
            domain: "Strimr.LiveTV",
            code: code,
            userInfo: userInfo,
        )
    }

    private static func plexCode(for error: PlexAPIError) -> Int {
        switch error {
        case .invalidURL: 1001
        case .invalidResponse: 1002
        case .missingAuthToken: 1003
        case .missingConnection: 1004
        case .unreachableServer: 1005
        case let .requestFailed(statusCode): statusCode
        case .decodingFailed: 1006
        }
    }

    private static func plexStatusCode(for error: PlexAPIError) -> Int? {
        guard case let .requestFailed(statusCode) = error else { return nil }
        return statusCode
    }

    private static func jellyfinCode(for error: JellyfinAPIError) -> Int {
        switch error {
        case .invalidServerURL: 1101
        case .unsupportedServer: 1102
        case .serverUnreachable: 1103
        case .invalidCredentials: 1104
        case .authenticationRequired: 1105
        case .permissionDenied: 1106
        case .itemUnavailable: 1107
        case .noPlayableSource: 1108
        case .recordingConflict: 1109
        case .invalidResponse: 1110
        case let .httpStatus(statusCode): statusCode
        }
    }

    private static func jellyfinStatusCode(for error: JellyfinAPIError) -> Int? {
        guard case let .httpStatus(statusCode) = error else { return nil }
        return statusCode
    }
}

struct LiveTVChannelIdentity: Hashable, Sendable {
    let providerID: String
    let lineupID: String?
    let dvrID: String?
}

struct LiveTVProgramIdentity: Hashable, Sendable {
    let providerID: String
    let channel: LiveTVChannelIdentity
}

struct LiveTVChannel: Identifiable, Hashable, Sendable {
    let providerID: String
    let title: String
    let callSign: String?
    let number: String?
    let thumbPath: String?
    let artPath: String?
    let lineupID: String?
    let dvrID: String?
    let isHD: Bool
    var isFavorite: Bool

    var identity: LiveTVChannelIdentity {
        LiveTVChannelIdentity(providerID: providerID, lineupID: lineupID, dvrID: dvrID)
    }

    var id: LiveTVChannelIdentity {
        identity
    }

    var displayTitle: String {
        let name = callSign?.nilIfEmpty ?? title
        guard let number = number?.nilIfEmpty else { return name }
        return "\(number) · \(name)"
    }
}

struct LiveTVProgram: Identifiable, Hashable, Sendable {
    let id: String
    let channelID: String
    let channelIdentity: LiveTVChannelIdentity
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
    var recordingID: String?
    let seriesRecordingID: String?
    var recordingStatus: DVRRecordingStatus?
    let providerGUID: String?

    var identity: LiveTVProgramIdentity {
        LiveTVProgramIdentity(providerID: id, channel: channelIdentity)
    }

    var isRecording: Bool {
        recordingStatus == .recording
    }

    var isScheduledForRecording: Bool {
        recordingStatus != nil || recordingID != nil || seriesRecordingID != nil
    }

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
    var programs: [LiveTVProgram]
}

struct LiveTVCaptureRange: Hashable, Sendable {
    let startDate: Date
    let endDate: Date

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }
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
        startsFromBeginning: Bool = false,
    ) {
        self.channels = channels
        self.selectedIndex = selectedIndex
        self.program = program
        self.startsFromBeginning = startsFromBeginning
    }

    var channel: LiveTVChannel {
        channels[selectedIndex]
    }
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
    let options: [DVRRecordingOption]

    init(
        id: String,
        title: String,
        isSeries: Bool,
        targetLibraryID: String?,
        targetLibraryTitle: String?,
        optionValues: [String: String],
        options: [DVRRecordingOption] = [],
    ) {
        self.id = id
        self.title = title
        self.isSeries = isSeries
        self.targetLibraryID = targetLibraryID
        self.targetLibraryTitle = targetLibraryTitle
        self.optionValues = optionValues
        self.options = options
    }
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
    let currentValue: String?

    init(
        id: String,
        title: String,
        summary: String?,
        kind: DVRRecordingOptionKind,
        defaultValue: String,
        currentValue: String? = nil,
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.kind = kind
        self.defaultValue = defaultValue
        self.currentValue = currentValue
    }

    var resolvedValue: String {
        currentValue ?? defaultValue
    }
}

enum DVRRecordingMode: Hashable, Sendable {
    case single
    case series
}

struct DVRRecordingModeTemplate: Hashable, Sendable {
    let options: [DVRRecordingOption]
    let defaultLibraryID: String?
}

struct DVRRecordingTemplate: Hashable, Sendable {
    let programID: String
    let single: DVRRecordingModeTemplate?
    let series: DVRRecordingModeTemplate?
    let preferredMode: DVRRecordingMode?
    let libraries: [Library]

    var supportsSingle: Bool {
        single != nil
    }

    var supportsSeries: Bool {
        series != nil
    }

    func template(for mode: DVRRecordingMode) -> DVRRecordingModeTemplate? {
        switch mode {
        case .single: single
        case .series: series
        }
    }
}

struct DVRRecordingRequest: Sendable {
    let program: LiveTVProgram
    let recordsSeries: Bool
    let targetLibraryID: String?
    let options: [String: String]
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
