import Foundation

struct PlaybackSettings: Codable, Equatable {
    var autoPlayNextEpisode = true
    var seekBackwardSeconds = 10
    var seekForwardSeconds = 10
    var player = PlaybackPlayer.mpv
    var subtitleScale = 100
}

struct InterfaceSettings: Codable, Equatable {
    var hiddenLibraryIds: [String] = []
    var navigationLibraryIds: [String] = []
}

struct DownloadSettings: Codable, Equatable {
    var showDownloadsAfterMovieDownload = true
    var showDownloadsAfterEpisodeDownload = false
    var showDownloadsAfterShowDownload = true
}

struct AppSettings: Codable, Equatable {
    var playback = PlaybackSettings()
    var interface = InterfaceSettings()
    var download = DownloadSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playback = try container.decodeIfPresent(PlaybackSettings.self, forKey: .playback) ?? PlaybackSettings()
        interface = try container.decodeIfPresent(InterfaceSettings.self, forKey: .interface) ?? InterfaceSettings()
        download = try container.decodeIfPresent(DownloadSettings.self, forKey: .download) ?? DownloadSettings()
    }
}
