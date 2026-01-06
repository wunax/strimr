import Foundation
import SwiftUI

struct VLCPlayerView: UIViewControllerRepresentable {
    var coordinator: Coordinator

    func makeUIViewController(context: Context) -> some UIViewController {
        let vlc = VLCPlayerViewController(options: coordinator.options)
        vlc.playDelegate = coordinator
        vlc.playUrl = coordinator.playUrl

        context.coordinator.player = vlc
        return vlc
    }

    func updateUIViewController(_: UIViewControllerType, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        coordinator
    }

    func play(_ url: URL) -> Self {
        coordinator.playUrl = url
        return self
    }

    func onPropertyChange(_ handler: @escaping (VLCPlayerViewController, PlayerProperty, Any?) -> Void) -> Self {
        coordinator.onPropertyChange = handler
        return self
    }

    func onPlaybackEnded(_ handler: @escaping () -> Void) -> Self {
        coordinator.onPlaybackEnded = handler
        return self
    }

    func onMediaLoaded(_ handler: @escaping () -> Void) -> Self {
        coordinator.onMediaLoaded = handler
        return self
    }

    @MainActor
    @Observable
    final class Coordinator: VLCPlayerDelegate, PlayerCoordinating {
        weak var player: VLCPlayerViewController?

        @ObservationIgnored var playUrl: URL?
        @ObservationIgnored var options = PlayerOptions()
        @ObservationIgnored var onPropertyChange: ((VLCPlayerViewController, PlayerProperty, Any?) -> Void)?
        @ObservationIgnored var onPlaybackEnded: (() -> Void)?
        @ObservationIgnored var onMediaLoaded: (() -> Void)?

        func play(_ url: URL) {
            player?.loadFile(url)
        }

        func togglePlayback() {
            player?.togglePause()
        }

        func pause() {
            player?.pause()
        }

        func resume() {
            player?.play()
        }

        func seek(to time: Double) {
            player?.seek(to: time)
        }

        func seek(by delta: Double) {
            player?.seek(by: delta)
        }

        func selectAudioTrack(id: Int?) {
            player?.setAudioTrack(id: id)
        }

        func selectSubtitleTrack(id: Int?) {
            player?.setSubtitleTrack(id: id)
        }

        func trackList() -> [PlayerTrack] {
            player?.trackList() ?? []
        }

        func destruct() {
            player?.destruct()
        }

        func propertyChange(player: VLCPlayerViewController, property: PlayerProperty, data: Any?) {
            onPropertyChange?(player, property, data)
        }

        func playbackEnded() {
            onPlaybackEnded?()
        }

        func fileLoaded() {
            onMediaLoaded?()
        }
    }
}
