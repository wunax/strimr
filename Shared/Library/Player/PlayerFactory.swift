import Foundation
import SwiftUI

enum PlayerFactory {
    static func makeCoordinator(for selection: PlaybackPlayer) -> any PlayerCoordinating {
        switch selection {
        case .mpv:
            return MPVPlayerView.Coordinator()
        case .vlc:
            return VLCPlayerView.Coordinator()
        }
    }

    static func makeView(
        selection: PlaybackPlayer,
        coordinator: any PlayerCoordinating,
        onPropertyChange: @escaping (PlayerProperty, Any?) -> Void,
        onPlaybackEnded: @escaping () -> Void
    ) -> AnyView {
        switch selection {
        case .mpv:
            guard let mpvCoordinator = coordinator as? MPVPlayerView.Coordinator else {
                assertionFailure("MPV coordinator expected")
                return AnyView(EmptyView())
            }
            return AnyView(
                MPVPlayerView(coordinator: mpvCoordinator)
                    .onPropertyChange { _, property, data in
                        onPropertyChange(property, data)
                    }
                    .onPlaybackEnded(onPlaybackEnded)
            )
        case .vlc:
            guard let vlcCoordinator = coordinator as? VLCPlayerView.Coordinator else {
                assertionFailure("VLC coordinator expected")
                return AnyView(EmptyView())
            }
            return AnyView(
                VLCPlayerView(coordinator: vlcCoordinator)
                    .onPropertyChange { _, property, data in
                        onPropertyChange(property, data)
                    }
                    .onPlaybackEnded(onPlaybackEnded)
            )
        }
    }
}
