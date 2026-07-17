import Foundation

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

struct SubtitleAppearance: Equatable {
    let fontSize: Int
    let textColor: SubtitleTextColor
    let fontWeight: SubtitleFontWeight
    let backgroundStrength: SubtitleBackgroundStrength
    let edgeStyle: SubtitleEdgeStyle
    let verticalPosition: SubtitleVerticalPosition
}

struct PlaybackSettings: Codable, Equatable {
    var autoPlayNextEpisode = true
    var losslessAudio = false
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
        autoPlayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoPlayNextEpisode) ?? true
        losslessAudio = try container.decodeIfPresent(Bool.self, forKey: .losslessAudio) ?? false
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
    var displaySeerrDiscoverTab = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenLibraryIds = try container.decodeIfPresent([String].self, forKey: .hiddenLibraryIds) ?? []
        navigationLibraryIds = try container.decodeIfPresent([String].self, forKey: .navigationLibraryIds) ?? []
        displayCollections = try container.decodeIfPresent(Bool.self, forKey: .displayCollections) ?? true
        displayPlaylists = try container.decodeIfPresent(Bool.self, forKey: .displayPlaylists) ?? true
        displaySeerrDiscoverTab = try container.decodeIfPresent(Bool.self, forKey: .displaySeerrDiscoverTab) ?? true
    }
}

struct DownloadSettings: Codable, Equatable {
    var wifiOnly = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wifiOnly = try container.decodeIfPresent(Bool.self, forKey: .wifiOnly) ?? true
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
