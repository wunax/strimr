import Foundation
import UIKit

#if os(tvOS)
    import TVVLCKit
#else
    import MobileVLCKit
#endif

final class VLCPlayerViewController: UIViewController, VLCMediaPlayerDelegate {
    private let options: PlayerOptions
    private lazy var mediaPlayer: VLCMediaPlayer = {
        let scaledValue = Int(round(Double(options.subtitleScale) * 0.5))
        return VLCMediaPlayer(options: ["--sub-text-scale=\(scaledValue)"])
    }()

    var playDelegate: VLCPlayerDelegate?
    var playUrl: URL?
    private var lastReportedTimeSeconds = -1.0
    private var hasNotifiedFileLoaded = false

    init(options: PlayerOptions) {
        self.options = options
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        mediaPlayer.stop()
        mediaPlayer.delegate = nil
        updateIdleTimer(isPlaying: false)
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
        hasNotifiedFileLoaded = false
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
        let durationSeconds = Double(mediaPlayer.media?.length.intValue ?? 0) / 1000.0
        let clampedTime = clampSeekTime(time, durationSeconds: durationSeconds)
        let milliseconds = max(0, Int32(clampedTime * 1000.0))
        mediaPlayer.time = VLCTime(int: milliseconds)
    }

    func seek(by delta: Double) {
        let currentMilliseconds = Double(mediaPlayer.time.intValue)
        let nextTime = (currentMilliseconds / 1000.0) + delta
        seek(to: nextTime)
    }

    func setPlaybackRate(_ rate: Float) {
        mediaPlayer.rate = max(0.1, rate)
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
            selectedIndex: Int(mediaPlayer.currentAudioTrackIndex),
        )
        let subtitleTracks = makeTracks(
            names: mediaPlayer.videoSubTitlesNames,
            indexes: mediaPlayer.videoSubTitlesIndexes,
            type: .subtitle,
            selectedIndex: Int(mediaPlayer.currentVideoSubTitleIndex),
        )

        return audioTracks + subtitleTracks
    }

    func destruct() {
        mediaPlayer.stop()
        mediaPlayer.delegate = nil
        mediaPlayer.drawable = nil
        updateIdleTimer(isPlaying: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        updateIdleTimer(isPlaying: false)
    }

    func mediaPlayerStateChanged(_: Notification) {
        let state = mediaPlayer.state
        let isBuffering = state == .opening || state == .buffering
        let isPaused = state == .paused || state == .stopped || state == .ended

        DispatchQueue.main.async {
            self.playDelegate?.propertyChange(player: self, property: .pause, data: isPaused)
            self.playDelegate?.propertyChange(player: self, property: .pausedForCache, data: isBuffering)
        }

        if !hasNotifiedFileLoaded, state == .playing || state == .paused {
            hasNotifiedFileLoaded = true
            DispatchQueue.main.async {
                self.playDelegate?.fileLoaded()
            }
        }

        if state == .ended {
            updateIdleTimer(isPlaying: false)
            DispatchQueue.main.async {
                self.playDelegate?.playbackEnded()
            }
        } else {
            updateIdleTimer(isPlaying: !isPaused)
        }
    }

    func mediaPlayerTimeChanged(_: Notification) {
        let timeSeconds = Double(mediaPlayer.time.intValue) / 1000.0
        let durationSeconds = Double(mediaPlayer.media?.length.intValue ?? 0) / 1000.0

        DispatchQueue.main.async {
            // VLC can remain in `.buffering` even while playback advances; time ticks are the most reliable signal.
            if timeSeconds != self.lastReportedTimeSeconds {
                self.lastReportedTimeSeconds = timeSeconds
                self.playDelegate?.propertyChange(player: self, property: .pausedForCache, data: false)
                self.updateIdleTimer(isPlaying: true)
            }
            self.playDelegate?.propertyChange(player: self, property: .timePos, data: timeSeconds)
            if durationSeconds > 0 {
                self.playDelegate?.propertyChange(player: self, property: .duration, data: durationSeconds)
            }
        }
    }

    private func updateIdleTimer(isPlaying: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = isPlaying
        }
    }

    private func makeTracks(
        names: [Any],
        indexes: [Any],
        type: PlayerTrack.TrackType,
        selectedIndex: Int,
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
                isSelected: id == selectedIndex,
            )
        }
    }

    private func clampSeekTime(_ time: Double, durationSeconds: Double) -> Double {
        guard durationSeconds > 0 else {
            return max(0, time)
        }
        // Avoid seeking to the exact end, which can trigger VLC edge-case behavior.
        let maxSeekTime = max(0, durationSeconds - 0.1)
        return min(max(0, time), maxSeekTime)
    }
}
