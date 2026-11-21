#if os(iOS) || os(macOS)
    import Foundation

    enum PlexDashboardTab: String, CaseIterable {
        case dashboard, history, topPlayed

        var title: String {
            switch self {
            case .dashboard: String(localized: "plex.dashboard.tab.dashboard")
            case .history: String(localized: "plex.dashboard.tab.history")
            case .topPlayed: String(localized: "plex.dashboard.tab.topPlayed")
            }
        }
    }

    enum PlexDashboardPeriod: Int, CaseIterable {
        case week = 7, month = 30, quarter = 90, all = 0

        var title: String {
            switch self {
            case .week: String(localized: "plex.dashboard.period.week")
            case .month: String(localized: "plex.dashboard.period.month")
            case .quarter: String(localized: "plex.dashboard.period.quarter")
            case .all: String(localized: "plex.dashboard.period.all")
            }
        }

        var start: Date? {
            guard self != .all else { return nil }
            return Calendar.current.date(
                byAdding: .day,
                value: 1 - rawValue,
                to: Calendar.current.startOfDay(for: Date()),
            )
        }
    }

    enum PlexDashboardMediaKind: String, CaseIterable {
        case movie, episode, track, other

        init(type: String) {
            self = Self(rawValue: type) ?? .other
        }

        init(metadataType: Int) {
            self = switch metadataType {
            case 1: .movie
            case 2, 3, 4: .episode
            case 8, 9, 10: .track
            default: .other
            }
        }

        var title: String {
            switch self {
            case .movie: String(localized: "plex.dashboard.kind.movie")
            case .episode: String(localized: "plex.dashboard.kind.episode")
            case .track: String(localized: "plex.dashboard.kind.track")
            case .other: String(localized: "plex.dashboard.kind.other")
            }
        }

        var symbol: String {
            switch self {
            case .movie: "film"
            case .episode: "tv"
            case .track: "music.note"
            case .other: "play.rectangle"
            }
        }
    }

    struct PlexDashboardUser: Identifiable {
        let id: String
        let name: String
        let thumb: String?
        let hasName: Bool
        var isCurrentAccount = false
    }

    struct PlexDashboardLibrary: Identifiable {
        let id: String
        let name: String
    }

    struct PlexDashboardPlay: Identifiable {
        let id: String
        let ratingKey: String
        let groupKey: String
        let title: String
        let subtitle: String?
        let kind: PlexDashboardMediaKind
        let thumb: String?
        let accountID: String?
        let userName: String?
        let userThumb: String?
        let viewedAt: Date?
        let player: String?
        let state: String?
        let decision: String?
        let progress: Double?
        let sessionID: String?
        let streamDetails: [PlexDashboardStreamDetail]

        var canOpenDetail: Bool {
            !ratingKey.isEmpty && (kind == .movie || kind == .episode)
        }
    }

    enum PlexDashboardStreamField {
        case app, state, position, connection, security, address, bandwidth
        case video, videoMode, videoOutput, audio, audioMode, audioOutput, subtitles, subtitleMode
        case hardwareDecode, hardwareEncode

        var title: String {
            switch self {
            case .app: String(localized: "plex.dashboard.stream.app")
            case .state: String(localized: "plex.dashboard.stream.state")
            case .position: String(localized: "plex.dashboard.stream.position")
            case .connection: String(localized: "plex.dashboard.stream.connection")
            case .security: String(localized: "plex.dashboard.stream.security")
            case .address: String(localized: "plex.dashboard.stream.address")
            case .bandwidth: String(localized: "plex.dashboard.stream.bandwidth")
            case .video: String(localized: "plex.dashboard.stream.video")
            case .videoMode: String(localized: "plex.dashboard.stream.videoMode")
            case .videoOutput: String(localized: "plex.dashboard.stream.videoOutput")
            case .audio: String(localized: "plex.dashboard.stream.audio")
            case .audioMode: String(localized: "plex.dashboard.stream.audioMode")
            case .audioOutput: String(localized: "plex.dashboard.stream.audioOutput")
            case .subtitles: String(localized: "plex.dashboard.stream.subtitles")
            case .subtitleMode: String(localized: "plex.dashboard.stream.subtitleMode")
            case .hardwareDecode: String(localized: "plex.dashboard.stream.hardwareDecode")
            case .hardwareEncode: String(localized: "plex.dashboard.stream.hardwareEncode")
            }
        }
    }

    struct PlexDashboardStreamDetail: Identifiable {
        let field: PlexDashboardStreamField
        let value: String

        var id: PlexDashboardStreamField {
            field
        }
    }

    /// The independently loaded parts of the dashboard, each with its own loading and error state.
    enum PlexDashboardLoad {
        case users, libraries, sessions, bandwidth, resources, activity, history, rankings
    }

    struct PlexDashboardHistoryPage {
        let items: [PlexDashboardPlay]
        let nextOffset: Int
        let hasMore: Bool
    }

    struct PlexDashboardPoint: Identifiable {
        let date: Date
        let series: String
        let value: Double

        var id: String {
            "\(date.timeIntervalSince1970)|\(series)"
        }
    }

    struct PlexDashboardActivity {
        let date: Date
        let accountID: String
        let kind: PlexDashboardMediaKind
        let plays: Int
        /// Plex's statistics/media duration is recorded playback time in seconds.
        let duration: TimeInterval
    }

    struct PlexDashboardTopUser: Identifiable {
        let id: String
        let plays: Int
        let duration: TimeInterval
        let breakdown: [PlexDashboardMediaKind: TimeInterval]
    }

    struct PlexDashboardTopTitle: Identifiable {
        let id: String
        let media: PlexDashboardPlay
        let plays: Int
        let accountIDs: Set<String>
    }

    enum PlexDashboardFormatting {
        static func bandwidth(_ megabits: Double) -> String {
            let useKilobits = megabits < 1
            let value = max(0, megabits) * (useKilobits ? 1000 : 1)
            return "\(value.formatted(.number.precision(.fractionLength(1)))) \(useKilobits ? "kbps" : "Mbps")"
        }

        static func duration(_ seconds: TimeInterval) -> String {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : (seconds >= 60 ? [.minute] : [.second])
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: max(0, seconds)) ?? ""
        }

        /// Maps a Plex stream, part or transcode decision to its label.
        static func decision(_ value: String?) -> String? {
            switch value {
            case "transcode": String(localized: "plex.dashboard.transcoding")
            case "copy", "directstream": String(localized: "plex.dashboard.directStream")
            case "directplay": String(localized: "plex.dashboard.directPlay")
            case "burn": String(localized: "plex.dashboard.stream.burnedIn")
            default: nil
            }
        }

        static func playbackState(_ value: String?) -> String? {
            switch value {
            case "playing": String(localized: "plex.dashboard.stream.playing")
            case "paused": String(localized: "plex.dashboard.stream.paused")
            case "buffering": String(localized: "plex.dashboard.stream.buffering")
            default: nil
            }
        }

        static func error(_ error: Error) -> String {
            if case let PlexAPIError.requestFailed(code) = error {
                switch code {
                case 401, 403: return String(localized: "plex.dashboard.error.access")
                case 402: return String(localized: "plex.dashboard.error.pass")
                case 404: return String(localized: "plex.dashboard.error.unsupported")
                default: break
                }
            }
            return String(localized: "plex.dashboard.error.load")
        }
    }

#endif
