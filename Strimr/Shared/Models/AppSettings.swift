import Foundation

struct PlaybackSettings: Codable, Equatable {
    var autoPlayNextEpisode = true
}

struct AppSettings: Codable, Equatable {
    var playback = PlaybackSettings()
}
