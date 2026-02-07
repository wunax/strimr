import Foundation

struct PlaybackSettings: Codable, Equatable {
    var autoPlayNextEpisode = true
    var seekBackwardSeconds = 10
    var seekForwardSeconds = 10
    var player = PlaybackPlayer.mpv
    var subtitleScale = 100

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoPlayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoPlayNextEpisode) ?? true
        seekBackwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekBackwardSeconds) ?? 10
        seekForwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekForwardSeconds) ?? 10
        player = try container.decodeIfPresent(PlaybackPlayer.self, forKey: .player) ?? .mpv
        subtitleScale = try container.decodeIfPresent(Int.self, forKey: .subtitleScale) ?? 100
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
