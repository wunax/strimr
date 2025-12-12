import Foundation
import SwiftUI

struct MPVPlayerView: UIViewControllerRepresentable {
    var coordinator: Coordinator
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let mpv =  MPVPlayerViewController()
        mpv.playDelegate = coordinator
        mpv.playUrl = coordinator.playUrl
        
        context.coordinator.player = mpv
        return mpv
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
    }
    
    public func makeCoordinator() -> Coordinator {
        coordinator
    }
    
    func play(_ url: URL) -> Self {
        coordinator.playUrl = url
        return self
    }
    
    func onPropertyChange(_ handler: @escaping (MPVPlayerViewController, String, Any?) -> Void) -> Self {
        coordinator.onPropertyChange = handler
        return self
    }

    func onPlaybackEnded(_ handler: @escaping () -> Void) -> Self {
        coordinator.onPlaybackEnded = handler
        return self
    }
    
    @MainActor
    @Observable
    public final class Coordinator: MPVPlayerDelegate {
        weak var player: MPVPlayerViewController?
        
        @ObservationIgnored var playUrl : URL?
        @ObservationIgnored var onPropertyChange: ((MPVPlayerViewController, String, Any?) -> Void)?
        @ObservationIgnored var onPlaybackEnded: (() -> Void)?
        
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

        func trackList() -> [MPVTrack] {
            player?.trackList() ?? []
        }
        
        func propertyChange(mpv: OpaquePointer, propertyName: String, data: Any?) {
            guard let player else { return }
            
            self.onPropertyChange?(player, propertyName, data)
        }

        func playbackEnded() {
            onPlaybackEnded?()
        }
    }
}
