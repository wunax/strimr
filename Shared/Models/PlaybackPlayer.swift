import Foundation

enum PlaybackPlayer: String, Codable, CaseIterable, Identifiable {
    case mpv
    case infuse

    var id: String {
        rawValue
    }

    var localizationKey: String {
        switch self {
        case .mpv:
            "settings.playback.player.mpv"
        case .infuse:
            "settings.playback.player.infuse"
        }
    }

    var isExternal: Bool {
        self == .infuse
    }
}

enum InternalPlaybackPlayer: String, CaseIterable, Identifiable {
    case mpv

    var id: String {
        rawValue
    }

    init?(player: PlaybackPlayer) {
        switch player {
        case .mpv:
            self = .mpv
        case .infuse:
            return nil
        }
    }
}
