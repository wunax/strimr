import AetherEngine
import Combine
import Foundation
import Observation

@MainActor
@Observable
final class AetherPlayerController {
    let engine: AetherEngine

    var isPaused = false
    var isBuffering = false
    var duration: Double?
    var position = 0.0
    var sourcePosition = 0.0
    var bufferedAhead = 0.0
    var videoFormatBadge: PlayerVideoFormatBadge?
    var subtitleCues: [SubtitleCue] = []
    var subtitleMaxCueDuration = 60.0
    var errorMessage: String?

    @ObservationIgnored var onMediaLoaded: (() -> Void)?
    @ObservationIgnored var onPlaybackEnded: (() -> Void)?

    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var selectedSubtitleTrackID: Int?
    @ObservationIgnored private var hasStartedPlayback = false
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var playbackRate: Float = 1.0

    init() {
        do {
            engine = try AetherEngine()
        } catch {
            fatalError("Failed to initialize AetherEngine: \(error)")
        }

        observeEngine()
    }

    func load(url: URL, startPosition: Double?, preferredAudioTrackID: Int?) {
        isStopping = false
        hasStartedPlayback = false
        selectedSubtitleTrackID = nil
        subtitleCues = []
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await engine.load(
                    url: url,
                    startPosition: startPosition,
                    options: LoadOptions(),
                    audioSourceStreamIndex: preferredAudioTrackID.map(Int32.init),
                )
                engine.setRate(playbackRate)
                onMediaLoaded?()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func togglePlayback() {
        engine.togglePlayPause()
    }

    func pause() {
        engine.pause()
    }

    func resume() {
        engine.play()
    }

    func seek(to time: Double) {
        Task { @MainActor [weak self] in
            await self?.engine.seek(to: time)
        }
    }

    func seek(by delta: Double) {
        seek(to: max(0, position + delta))
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        engine.setRate(rate)
    }

    func selectAudioTrack(id: Int?) {
        guard let id else { return }
        engine.selectAudioTrack(index: id)
    }

    func selectSubtitleTrack(id: Int?) {
        selectedSubtitleTrackID = id
        guard let id else {
            engine.clearSubtitle()
            subtitleCues = []
            return
        }
        engine.selectSubtitleTrack(index: id)
        subtitleCues = engine.subtitleCues
    }

    func trackList() -> [PlayerTrack] {
        let audio = engine.audioTracks.map { track in
            PlayerTrack(
                id: track.id,
                ffIndex: track.id,
                type: .audio,
                title: track.name,
                language: track.language,
                codec: track.codec,
                isDefault: track.isDefault,
                isSelected: engine.activeAudioTrackIndex == track.id,
            )
        }

        let subtitles = engine.subtitleTracks.map { track in
            PlayerTrack(
                id: track.id,
                ffIndex: track.id,
                type: .subtitle,
                title: track.name,
                language: track.language,
                codec: track.codec,
                isDefault: track.isDefault,
                isSelected: selectedSubtitleTrackID == track.id,
            )
        }

        return audio + subtitles
    }

    func stop() {
        isStopping = true
        engine.stop()
    }

    private func observeEngine() {
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleState(state)
            }
            .store(in: &cancellables)

        engine.$isBuffering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isBuffering in
                self?.isBuffering = isBuffering
            }
            .store(in: &cancellables)

        engine.clock.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.position = time
            }
            .store(in: &cancellables)

        engine.clock.$sourceTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.sourcePosition = time
            }
            .store(in: &cancellables)

        engine.clock.$bufferedPosition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bufferedPosition in
                guard let self else { return }
                bufferedAhead = max(0, bufferedPosition - position)
            }
            .store(in: &cancellables)

        engine.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                self?.duration = duration > 0 ? duration : nil
            }
            .store(in: &cancellables)

        engine.$videoFormat
            .receive(on: DispatchQueue.main)
            .sink { [weak self] format in
                self?.videoFormatBadge = Self.videoFormatBadge(for: format)
            }
            .store(in: &cancellables)

        engine.$subtitleCues
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cues in
                guard let self else { return }
                subtitleCues = cues
                subtitleMaxCueDuration = cues.reduce(60.0) {
                    max($0, $1.endTime - $1.startTime)
                }
            }
            .store(in: &cancellables)
    }

    private func handleState(_ state: PlaybackState) {
        switch state {
        case .playing:
            hasStartedPlayback = true
            isPaused = false
        case .paused:
            isPaused = true
        case .loading, .seeking:
            break
        case .error(let message):
            errorMessage = message
        case .ended:
            isPaused = false
            guard hasStartedPlayback, !isStopping else { return }
            hasStartedPlayback = false
            onPlaybackEnded?()
        case .idle:
            isPaused = false
        }
    }

    private static func videoFormatBadge(for format: VideoFormat) -> PlayerVideoFormatBadge? {
        switch format {
        case .sdr:
            nil
        case .hdr10:
            .hdr10
        case .hdr10Plus:
            .hdr10Plus
        case .dolbyVision:
            .dolbyVision
        case .hlg:
            .hlg
        }
    }
}
