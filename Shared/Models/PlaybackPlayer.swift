import Foundation

enum PlaybackPlayer: String, Codable, CaseIterable, Identifiable {
    case vlc
    case mpv
    case infuse

    var id: String {
        rawValue
    }

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
    #if !os(visionOS)
    case vlc
    #endif
    case mpv

    var id: String {
        rawValue
    }

    init?(player: PlaybackPlayer) {
        switch player {
        #if !os(visionOS)
        case .vlc:
            self = .vlc
        #endif
        case .mpv:
            self = .mpv
        case .infuse:
            return nil
        #if os(visionOS)
        default:
            return nil
        #endif
        }
    }
}
