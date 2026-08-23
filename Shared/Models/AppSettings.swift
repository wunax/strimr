import Foundation

enum SpoilerProtectionLevel: String, Codable, CaseIterable, Hashable {
    case off
    case thumbnails
    case full

    var title: String {
        switch self {
        case .off:
            String(localized: "settings.interface.spoilerProtection.off")
        case .thumbnails:
            String(localized: "settings.interface.spoilerProtection.thumbnails")
        case .full:
            String(localized: "settings.interface.spoilerProtection.full")
        }
    }
}

enum SubtitleTextColor: String, Codable, CaseIterable, Hashable {
    case white
    case yellow
    case cyan
}

enum SubtitleFontWeight: String, Codable, CaseIterable, Hashable {
    case regular
    case medium
    case semibold
    case bold
}

enum SubtitleBackgroundStrength: String, Codable, CaseIterable, Hashable {
    case none
    case subtle
    case standard
    case strong
}

enum SubtitleEdgeStyle: String, Codable, CaseIterable, Hashable {
    case shadow
    case outline
    case none
}

enum SubtitleVerticalPosition: String, Codable, CaseIterable, Hashable {
    case bottom
    case middle
    case top
}

enum NextEpisodeAutoplay: String, Codable, CaseIterable, Hashable {
    case disabled
    case immediately
    case after5Seconds
    case after10Seconds
    case after15Seconds
    case after30Seconds

    var delaySeconds: Int? {
        switch self {
        case .disabled:
            nil
        case .immediately:
            0
        case .after5Seconds:
            5
        case .after10Seconds:
            10
        case .after15Seconds:
            15
        case .after30Seconds:
            30
        }
    }

    var isEnabled: Bool {
        self != .disabled
    }

    var title: String {
        switch self {
        case .disabled:
            String(localized: "settings.playback.nextEpisodeAutoplay.disabled")
        case .immediately:
            String(localized: "settings.playback.nextEpisodeAutoplay.immediately")
        case .after5Seconds:
            String(localized: "settings.playback.nextEpisodeAutoplay.after5Seconds")
        case .after10Seconds:
            String(localized: "settings.playback.nextEpisodeAutoplay.after10Seconds")
        case .after15Seconds:
            String(localized: "settings.playback.nextEpisodeAutoplay.after15Seconds")
        case .after30Seconds:
            String(localized: "settings.playback.nextEpisodeAutoplay.after30Seconds")
        }
    }
}

struct SubtitleAppearance: Equatable {
    let fontSize: Int
    let textColor: SubtitleTextColor
    let fontWeight: SubtitleFontWeight
    let backgroundStrength: SubtitleBackgroundStrength
    let edgeStyle: SubtitleEdgeStyle
    let verticalPosition: SubtitleVerticalPosition
}

struct PlaybackSettings: Codable, Equatable {
    var qualityPreset = TranscodeQualityPreset.original
    var nextEpisodeAutoplay = NextEpisodeAutoplay.after15Seconds
    var autoSkipIntros = false
    var autoSkipCredits = false
    var losslessAudio = false
    var showChaptersOnTimeline = true
    var showEndsAtTime = true
    var showClock = false
    var showScrubThumbnailPreviews = true
    var generateMissingScrubThumbnailPreviews = true
    var styledASSSubtitles = true
    var seekBackwardSeconds = 10
    var seekForwardSeconds = 10
    var subtitleFontSize = defaultSubtitleFontSize
    var subtitleTextColor = SubtitleTextColor.white
    var subtitleFontWeight = SubtitleFontWeight.semibold
    var subtitleBackgroundStrength = SubtitleBackgroundStrength.standard
    var subtitleEdgeStyle = SubtitleEdgeStyle.shadow
    var subtitleVerticalPosition = SubtitleVerticalPosition.bottom

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        qualityPreset = try container.decodeIfPresent(
            TranscodeQualityPreset.self,
            forKey: .qualityPreset,
        ) ?? .original
        nextEpisodeAutoplay = try container.decodeIfPresent(
            NextEpisodeAutoplay.self,
            forKey: .nextEpisodeAutoplay,
        ) ?? .after15Seconds
        autoSkipIntros = try container.decodeIfPresent(Bool.self, forKey: .autoSkipIntros) ?? false
        autoSkipCredits = try container.decodeIfPresent(Bool.self, forKey: .autoSkipCredits) ?? false
        losslessAudio = try container.decodeIfPresent(Bool.self, forKey: .losslessAudio) ?? false
        showChaptersOnTimeline = try container.decodeIfPresent(
            Bool.self,
            forKey: .showChaptersOnTimeline,
        ) ?? true
        showEndsAtTime = try container.decodeIfPresent(
            Bool.self,
            forKey: .showEndsAtTime,
        ) ?? true
        showClock = try container.decodeIfPresent(Bool.self, forKey: .showClock) ?? false
        showScrubThumbnailPreviews = try container.decodeIfPresent(
            Bool.self,
            forKey: .showScrubThumbnailPreviews,
        ) ?? true
        generateMissingScrubThumbnailPreviews = try container.decodeIfPresent(
            Bool.self,
            forKey: .generateMissingScrubThumbnailPreviews,
        ) ?? true
        styledASSSubtitles = try container.decodeIfPresent(Bool.self, forKey: .styledASSSubtitles) ?? true
        seekBackwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekBackwardSeconds) ?? 10
        seekForwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekForwardSeconds) ?? 10
        subtitleFontSize = (try? container.decode(Int.self, forKey: .subtitleFontSize))
            ?? Self.defaultSubtitleFontSize
        subtitleTextColor = (try? container.decode(SubtitleTextColor.self, forKey: .subtitleTextColor))
            ?? .white
        subtitleFontWeight = (try? container.decode(SubtitleFontWeight.self, forKey: .subtitleFontWeight))
            ?? .semibold
        subtitleBackgroundStrength = (
            try? container.decode(SubtitleBackgroundStrength.self, forKey: .subtitleBackgroundStrength),
        )
            ?? .standard
        subtitleEdgeStyle = (try? container.decode(SubtitleEdgeStyle.self, forKey: .subtitleEdgeStyle))
            ?? .shadow
        subtitleVerticalPosition = (
            try? container.decode(SubtitleVerticalPosition.self, forKey: .subtitleVerticalPosition),
        )
            ?? .bottom
    }

    var subtitleAppearance: SubtitleAppearance {
        SubtitleAppearance(
            fontSize: subtitleFontSize,
            textColor: subtitleTextColor,
            fontWeight: subtitleFontWeight,
            backgroundStrength: subtitleBackgroundStrength,
            edgeStyle: subtitleEdgeStyle,
            verticalPosition: subtitleVerticalPosition,
        )
    }

    mutating func resetSubtitleAppearance() {
        subtitleFontSize = Self.defaultSubtitleFontSize
        subtitleTextColor = .white
        subtitleFontWeight = .semibold
        subtitleBackgroundStrength = .standard
        subtitleEdgeStyle = .shadow
        subtitleVerticalPosition = .bottom
    }

    private static var defaultSubtitleFontSize: Int {
        #if os(tvOS)
            32
        #else
            20
        #endif
    }
}

struct InterfaceSettings: Codable, Equatable {
    var hiddenLibraryIds: [String] = []
    var navigationLibraryIds: [String] = []
    var displayCollections = true
    var displayPlaylists = true
    var displayFavoritesTab = false
    var displayDownloadsTab = false
    var displayLiveTVTab = true
    var displaySeerrDiscoverTab = true
    var multiServerSearchEnabled = true
    var spoilerProtection = SpoilerProtectionLevel.off

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenLibraryIds = try container.decodeIfPresent([String].self, forKey: .hiddenLibraryIds) ?? []
        navigationLibraryIds = try container.decodeIfPresent([String].self, forKey: .navigationLibraryIds) ?? []
        displayCollections = try container.decodeIfPresent(Bool.self, forKey: .displayCollections) ?? true
        displayPlaylists = try container.decodeIfPresent(Bool.self, forKey: .displayPlaylists) ?? true
        displayFavoritesTab = try container.decodeIfPresent(Bool.self, forKey: .displayFavoritesTab) ?? false
        displayDownloadsTab = try container.decodeIfPresent(Bool.self, forKey: .displayDownloadsTab) ?? false
        displayLiveTVTab = try container.decodeIfPresent(Bool.self, forKey: .displayLiveTVTab) ?? true
        displaySeerrDiscoverTab = try container.decodeIfPresent(Bool.self, forKey: .displaySeerrDiscoverTab) ?? true
        multiServerSearchEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .multiServerSearchEnabled,
        ) ?? true
        spoilerProtection = (try? container.decode(SpoilerProtectionLevel.self, forKey: .spoilerProtection)) ?? .off
    }
}

struct DownloadSettings: Codable, Equatable {
    var wifiOnly = true
    var qualityPreset = TranscodeQualityPreset.original

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wifiOnly = try container.decodeIfPresent(Bool.self, forKey: .wifiOnly) ?? true
        qualityPreset = try container.decodeIfPresent(
            TranscodeQualityPreset.self,
            forKey: .qualityPreset,
        ) ?? .original
    }
}

struct AppSettings: Codable, Equatable {
    var playback = PlaybackSettings()
    var interface = InterfaceSettings()
    var downloads = DownloadSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playback = try container.decodeIfPresent(PlaybackSettings.self, forKey: .playback) ?? PlaybackSettings()
        interface = try container.decodeIfPresent(InterfaceSettings.self, forKey: .interface) ?? InterfaceSettings()
        downloads = try container.decodeIfPresent(DownloadSettings.self, forKey: .downloads) ?? DownloadSettings()
    }
}
