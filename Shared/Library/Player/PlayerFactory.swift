import Foundation
import SwiftUI

enum PlayerFactory {
    static func makeCoordinator(
        for selection: InternalPlaybackPlayer,
        options: PlayerOptions,
    ) -> any PlayerCoordinating {
        switch selection {
        case .mpv:
            let coordinator = MPVPlayerView.Coordinator()
            coordinator.options = options
            return coordinator
        #if !os(visionOS)
        case .vlc:
            let coordinator = VLCPlayerView.Coordinator()
            coordinator.options = options
            return coordinator
        #endif
        }
    }

    static func makeView(
        selection: InternalPlaybackPlayer,
        coordinator: any PlayerCoordinating,
        onPropertyChange: @escaping (PlayerProperty, Any?) -> Void,
        onPlaybackEnded: @escaping () -> Void,
        onMediaLoaded: @escaping () -> Void,
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
                    .onMediaLoaded(onMediaLoaded),
            )
        #if !os(visionOS)
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
                    .onMediaLoaded(onMediaLoaded),
            )
        #endif
        }
    }
}
