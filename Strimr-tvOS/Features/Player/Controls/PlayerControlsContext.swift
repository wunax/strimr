import SwiftUI

/// What the player controls show, shared by every controls style.
struct PlayerControlsState {
    var media: MediaItem?
    var isPaused: Bool
    var badges: [PlayerControlBadge]
    var duration: Double?
    var bufferedAhead: Double
    var bufferBasePosition: Double
    var playbackRate: Float
    var showsEndsAtTime: Bool
    var showsClock: Bool
    var isScrubbing: Bool
    var sleepTimer: SleepTimer
    var chapters: [MediaChapter]
    var showsChaptersOnTimeline: Bool
    var skipSegments: [SkipSegment]
    var scrubPreview: PlayerScrubPreview?
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int
    var skipMarkerTitle: String?
    var isSharePlay: Bool
    var hasInfoPanel: Bool
    var live: PlayerLiveState?
    var settingsControl: PlayerSettingsControl?
    var showsSubtitleOffsetIndicator: Bool
    var settingsFocusGeneration: Int
    var isShowingPanel: Bool
    /// Only built for the system style, which shows the settings as anchored menus.
    var menus: PlayerSystemMenus?
    /// What the system style tabs show below the timeline. Nil without tabs, as in Live TV.
    var tabs: PlayerTabsContent?
    /// The system style tabs are open, or asked to open with the remote while the controls were hidden.
    var isShowingTabs = false

    var seekBackwardSymbol: String {
        Self.seekSymbol(prefix: "gobackward", seconds: seekBackwardSeconds)
    }

    var seekForwardSymbol: String {
        Self.seekSymbol(prefix: "goforward", seconds: seekForwardSeconds)
    }

    /// SF Symbols only number some intervals; the others fall back on the plain arrow.
    private static func seekSymbol(prefix: String, seconds: Int) -> String {
        let supported = [5, 10, 15, 30, 45, 60]
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
}

struct PlayerTabsContent {
    var services: MediaServices?
    var queueItems: [PlaybackQueueItem]
    var queueCurrentIndex: Int
    var showsQueue: Bool
}

struct PlayerSystemMenus {
    /// Resolved only for the open menu, since the player body runs on every position update.
    var sections: (SystemPlayerMenu) -> [PlayerMenuSection]
}

struct PlayerLiveState {
    var behindLiveSeconds: Double
    var isAtLiveEdge: Bool
    var canSwitchPreviousChannel: Bool
    var canSwitchNextChannel: Bool
}

/// What the player controls can do, shared by every controls style.
struct PlayerControlsActions {
    var playPause: () -> Void
    var seekBackward: () -> Void
    var seekForward: () -> Void
    var scrubbingChanged: (Bool) -> Void
    var scrubbingCancelled: () -> Void
    var skipMarker: (() -> Void)?
    var showInfoPanel: () -> Void
    var userInteraction: () -> Void
    var showAudioSettings: () -> Void
    var showSubtitleSettings: () -> Void
    var showSpeedSettings: () -> Void
    var showSettings: () -> Void
    var goLive: () -> Void
    var showLiveChannels: () -> Void
    var previousChannel: () -> Void
    var nextChannel: () -> Void
    /// A system style menu opened or closed, which holds the controls on screen meanwhile.
    var menuPresentationChanged: (Bool) -> Void
    var tabsPresentationChanged: (Bool) -> Void
    var selectChapter: (MediaChapter) -> Void
    var restartFromBeginning: () -> Void
    var selectQueueItem: (Int) -> Void
}

struct PlayerControlBadge: Identifiable {
    var id: String
    var title: String
    var systemImage: String?

    static func playback(resolution: String?, format: PlayerVideoFormatBadge?) -> [PlayerControlBadge] {
        var badges: [PlayerControlBadge] = []
        if let resolution {
            badges.append(PlayerControlBadge(id: "resolution", title: resolution))
        }
        if let format {
            badges.append(PlayerControlBadge(id: format.id, title: format.title, systemImage: "sparkles"))
        }
        return badges
    }
}

enum PlayerSettingsControl {
    case audio, subtitle, speed, settings
}

/// Room the controls of a style take over the video, so subtitles, messages and statistics stay clear of them.
struct PlayerControlsMetrics {
    var subtitleInset: CGFloat
    /// With the info panel or the tabs open.
    var expandedSubtitleInset: CGFloat
    var feedbackBottomInset: CGFloat
    var statisticsTopInset: CGFloat
    var adjustmentBarBottomInset: CGFloat

    static let classic = PlayerControlsMetrics(
        subtitleInset: 380,
        expandedSubtitleInset: 440,
        feedbackBottomInset: 330,
        statisticsTopInset: 150,
        adjustmentBarBottomInset: 380,
    )

    static let system = PlayerControlsMetrics(
        subtitleInset: 340,
        expandedSubtitleInset: 560,
        feedbackBottomInset: 340,
        statisticsTopInset: 110,
        adjustmentBarBottomInset: 340,
    )
}

extension PlayerControlsStyle {
    var metrics: PlayerControlsMetrics {
        switch self {
        case .classic: .classic
        case .system: .system
        }
    }
}
