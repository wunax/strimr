import Foundation

enum PlaybackPlayer: String, Codable, CaseIterable, Identifiable {
    case vlc
    case mpv
    case infuse

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .mpv:
            "settings.playback.player.mpv"
        case .vlc:
            "settings.playback.player.vlc"
        case .infuse:
            "settings.playback.player.infuse"
        }
    }

    var isExternal: Bool {
        self == .infuse
    }
}

enum InternalPlaybackPlayer: String, CaseIterable, Identifiable {
    case vlc
    case mpv

    var id: String { rawValue }

    init?(player: PlaybackPlayer) {
        switch player {
        case .vlc:
            self = .vlc
        case .mpv:
            self = .mpv
        case .infuse:
            return nil
        }
    }
}
