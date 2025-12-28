import Foundation
import UIKit

#if os(tvOS)
import TVVLCKit
#else
import MobileVLCKit
#endif

final class VLCPlayerViewController: UIViewController, VLCMediaPlayerDelegate {
    private let mediaPlayer = VLCMediaPlayer()
    var playDelegate: VLCPlayerDelegate?
    var playUrl: URL?

    deinit {
        mediaPlayer.stop()
        mediaPlayer.delegate = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        mediaPlayer.drawable = view
        mediaPlayer.delegate = self

        if let url = playUrl {
            loadFile(url)
        }
    }

    func loadFile(_ url: URL) {
        mediaPlayer.media = VLCMedia(url: url)
        mediaPlayer.play()
    }

    func togglePause() {
        mediaPlayer.isPlaying ? pause() : play()
    }

    func play() {
        mediaPlayer.play()
    }

    func pause() {
        mediaPlayer.pause()
    }

    func seek(to time: Double) {
        let milliseconds = max(0, Int32(time * 1000.0))
        mediaPlayer.time = VLCTime(int: milliseconds)
    }

    func seek(by delta: Double) {
        let currentMilliseconds = Double(mediaPlayer.time.intValue)
        let nextTime = (currentMilliseconds / 1000.0) + delta
        seek(to: nextTime)
    }

    func setAudioTrack(id: Int?) {
        let trackID = id ?? -1
        mediaPlayer.currentAudioTrackIndex = Int32(trackID)
    }

    func setSubtitleTrack(id: Int?) {
        let trackID = id ?? -1
        mediaPlayer.currentVideoSubTitleIndex = Int32(trackID)
    }

    func trackList() -> [PlayerTrack] {        
        let audioTracks = makeTracks(
            names: mediaPlayer.audioTrackNames,
            indexes: mediaPlayer.audioTrackIndexes,
            type: .audio,
            selectedIndex: Int(mediaPlayer.currentAudioTrackIndex)
        )
        let subtitleTracks = makeTracks(
            names: mediaPlayer.videoSubTitlesNames,
            indexes: mediaPlayer.videoSubTitlesIndexes,
            type: .subtitle,
            selectedIndex: Int(mediaPlayer.currentVideoSubTitleIndex)
        )

        return audioTracks + subtitleTracks
    }

    func destruct() {
        mediaPlayer.stop()
        mediaPlayer.delegate = nil
        mediaPlayer.drawable = nil
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        let state = mediaPlayer.state
        let isBuffering = state == .opening || state == .buffering
        let isPaused = state == .paused || state == .stopped || state == .ended

        DispatchQueue.main.async {
            self.playDelegate?.propertyChange(player: self, property: .pause, data: isPaused)
            self.playDelegate?.propertyChange(player: self, property: .pausedForCache, data: isBuffering)
        }

        if state == .ended {
            DispatchQueue.main.async {
                self.playDelegate?.playbackEnded()
            }
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let timeSeconds = Double(mediaPlayer.time.intValue) / 1000.0
        let durationSeconds = Double(mediaPlayer.media?.length.intValue ?? 0) / 1000.0

        DispatchQueue.main.async {
            self.playDelegate?.propertyChange(player: self, property: .timePos, data: timeSeconds)
            if durationSeconds > 0 {
                self.playDelegate?.propertyChange(player: self, property: .duration, data: durationSeconds)
            }
        }
    }

    private func makeTracks(
        names: [Any],
        indexes: [Any],
        type: PlayerTrack.TrackType,
        selectedIndex: Int
    ) -> [PlayerTrack] {
        let paired = zip(names, indexes)
        return paired.compactMap { name, index in
            let id: Int
            if let number = index as? NSNumber {
                id = number.intValue
            } else if let intValue = index as? Int {
                id = intValue
            } else {
                return nil
            }
            let title = name as? String
            return PlayerTrack(
                id: id,
                ffIndex: id,
                type: type,
                title: title,
                language: nil,
                codec: nil,
                isDefault: false,
                isSelected: id == selectedIndex
            )
        }
    }
}
