import AetherEngine
import AVFoundation
import Combine
import CoreGraphics
import Foundation
import Observation
import SwiftUI

struct PlayerScrubPreview {
    var position: Double
    var image: CGImage?
}

@MainActor
@Observable
final class PlayerController {
    fileprivate let engine: AetherEngine

    var isPaused = false
    var isBuffering = false
    var duration: Double?
    var position = 0.0
    var sourcePosition = 0.0
    var bufferedAhead = 0.0
    var sourceVideoSize: CGSize?
    var videoFormatBadge: PlayerVideoFormatBadge?
    var subtitleCues: [SubtitleCue] = []
    var subtitleMaxCueDuration = 60.0
    var errorMessage: String?
    private(set) var scrubPreview: PlayerScrubPreview?
    private(set) var volume: Float = 1.0
    private(set) var isCoordinatedPlayback = false

    var isMuted: Bool {
        volume == 0
    }

    @ObservationIgnored var onMediaLoaded: (() -> Void)?
    @ObservationIgnored var onPlaybackEnded: (() -> Void)?

    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var coordinatedPlaybackIdentifier: String?
    @ObservationIgnored private var selectedSubtitleTrackID: Int?
    @ObservationIgnored private var hasStartedPlayback = false
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var playbackRate: Float = 1.0
    @ObservationIgnored private var lastAudibleVolume: Float = 1.0
    @ObservationIgnored private var scrubBIFTask: Task<Void, Never>?
    @ObservationIgnored private var scrubAetherTask: Task<Void, Never>?
    @ObservationIgnored private var scrubExtractorDwellTask: Task<Void, Never>?
    @ObservationIgnored private var scrubBIFPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var scrubBIFProvider: PlexBIFThumbnailProvider?
    @ObservationIgnored private var scrubFrameExtractor: FrameExtractor?
    @ObservationIgnored private var scrubExtractorRequestGeneration: Int?
    @ObservationIgnored private var scrubPreviewGeneration = 0
    @ObservationIgnored private var scrubTargetGeneration = 0
    @ObservationIgnored private var activeScrubBucket: Int?
    @ObservationIgnored private var isScrubPreviewing = false

    private let scrubBucketDuration = 10.0
    private let extractorThumbnailDelay: Duration = .milliseconds(800)
    private let scrubThumbnailWidth = 320

    init() {
        do {
            engine = try AetherEngine()
        } catch {
            fatalError("Failed to initialize player engine: \(error)")
        }

        observeEngine()
    }

    func load(
        url: URL,
        startPosition: Double?,
        preferredAudioTrackID: Int?,
        losslessAudio: Bool,
        scrubThumbnailSource: PlexBIFSource? = nil,
        autoplay: Bool = true,
    ) {
        resetScrubPreviewSession()
        scrubBIFProvider = scrubThumbnailSource.map {
            PlexBIFThumbnailProvider(source: $0)
        }
        isStopping = false
        hasStartedPlayback = false
        selectedSubtitleTrackID = nil
        subtitleCues = []
        sourceVideoSize = nil
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let sourceProbe = try await engine.load(
                    url: url,
                    startPosition: startPosition,
                    options: LoadOptions(
                        audioBridgeMode: losslessAudio ? .lossless : .surroundCompat,
                        autoplay: autoplay,
                    ),
                    audioSourceStreamIndex: preferredAudioTrackID.map(Int32.init),
                )
                if let sourceProbe,
                   sourceProbe.videoWidth > 0,
                   sourceProbe.videoHeight > 0
                {
                    sourceVideoSize = CGSize(
                        width: Int(sourceProbe.videoWidth),
                        height: Int(sourceProbe.videoHeight),
                    )
                }
                if !isCoordinatedPlayback {
                    engine.setRate(playbackRate)
                }
                if !engine.isLive, let scrubBIFProvider {
                    scrubBIFPreparationTask = Task {
                        await scrubBIFProvider.prepare()
                    }
                }
                onMediaLoaded?()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
                errorMessage = error.localizedDescription
            }
        }
    }

    func togglePlayback() {
        if isCoordinatedPlayback {
            engine.playbackCoordinator.coordinateRateChange(
                to: isPaused ? playbackRate : 0,
                options: [],
            )
        } else {
            engine.togglePlayPause()
        }
    }

    func pause() {
        if isCoordinatedPlayback {
            engine.playbackCoordinator.coordinateRateChange(to: 0, options: [])
        } else {
            engine.pause()
        }
    }

    func resume() {
        if isCoordinatedPlayback {
            engine.playbackCoordinator.coordinateRateChange(to: playbackRate, options: [])
        } else {
            engine.play()
        }
    }

    func seek(to time: Double) {
        if isCoordinatedPlayback {
            engine.playbackCoordinator.coordinateSeek(
                to: CMTime(seconds: time, preferredTimescale: 600),
                options: [],
            )
            return
        }
        Task { @MainActor [weak self] in
            await self?.engine.seek(to: time)
        }
    }

    func seek(by delta: Double) {
        seek(to: max(0, position + delta))
    }

    func beginScrubPreviewing(at position: Double) {
        isScrubPreviewing = true
        updateScrubPreview(to: position)
    }

    func updateScrubPreview(to position: Double) {
        guard isScrubPreviewing, position.isFinite else { return }

        let target = max(0, position)
        scrubTargetGeneration &+= 1
        cancelInFlightScrubExtraction()
        let bucket = Int(floor(target / scrubBucketDuration))
        let bucketChanged = activeScrubBucket != bucket

        if bucketChanged {
            activeScrubBucket = bucket
            scrubPreviewGeneration &+= 1
            scrubBIFTask?.cancel()
            scrubAetherTask?.cancel()
            scrubPreview = PlayerScrubPreview(position: target, image: nil)
            requestBucketThumbnails(
                target: target,
                bucket: bucket,
                generation: scrubPreviewGeneration,
            )
        } else {
            scrubPreview = PlayerScrubPreview(
                position: target,
                image: scrubPreview?.image,
            )
        }

        scheduleExtractorFallback(
            target: target,
            targetGeneration: scrubTargetGeneration,
        )
    }

    func endScrubPreviewing() {
        isScrubPreviewing = false
        scrubPreviewGeneration &+= 1
        scrubTargetGeneration &+= 1
        activeScrubBucket = nil
        scrubBIFTask?.cancel()
        scrubBIFTask = nil
        scrubAetherTask?.cancel()
        scrubAetherTask = nil
        scrubExtractorDwellTask?.cancel()
        scrubExtractorDwellTask = nil
        cancelInFlightScrubExtraction()
        scrubPreview = nil
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isCoordinatedPlayback {
            engine.playbackCoordinator.coordinateRateChange(to: rate, options: [])
        } else {
            engine.setRate(rate)
        }
    }

    func setVolume(_ newVolume: Float) {
        let clampedVolume = min(max(newVolume, 0), 1)
        volume = clampedVolume
        if clampedVolume > 0 {
            lastAudibleVolume = clampedVolume
        }
        engine.volume = clampedVolume
    }

    func toggleMute() {
        if isMuted {
            setVolume(lastAudibleVolume)
        } else {
            lastAudibleVolume = volume
            setVolume(0)
        }
    }

    var playbackCoordinator: AVDelegatingPlaybackCoordinator {
        engine.playbackCoordinator
    }

    func beginCoordinatedPlayback(
        identifier: String,
        initialTime: Double,
        initialRate: Float = 0,
    ) {
        isCoordinatedPlayback = true
        coordinatedPlaybackIdentifier = identifier
        engine.transitionToCoordinatedPlaybackItem(
            identifier: identifier,
            initialTime: initialTime,
            initialRate: initialRate,
        )
    }

    func reconcileCoordinatedPlaybackAfterLoad(
        identifier: String,
        initialTime: Double,
    ) {
        guard isCoordinatedPlayback,
              coordinatedPlaybackIdentifier == identifier
        else {
            beginCoordinatedPlayback(
                identifier: identifier,
                initialTime: initialTime,
            )
            return
        }

        // The item was already registered when the player attached. Re-registering it here with
        // an initial rate of zero can overwrite a play command that arrived while media loaded.
        // Ask the coordinator to replay its latest session state onto the now-loaded transport.
        engine.playbackCoordinator.reapplyCurrentItemStateToPlaybackControlDelegate()
    }

    func beginCoordinatedPlaybackFromCurrentState(identifier: String) {
        beginCoordinatedPlayback(
            identifier: identifier,
            initialTime: position,
            initialRate: isPaused ? 0 : playbackRate,
        )
    }

    func beginCoordinatedPlaybackResumingFromCurrentState(identifier: String) {
        beginCoordinatedPlayback(
            identifier: identifier,
            initialTime: position,
            initialRate: playbackRate,
        )
    }

    func endCoordinatedPlayback(continueLocally: Bool) {
        let intendedRate = engine.coordinatedPlaybackIntendedRate
        engine.endCoordinatedPlayback()
        isCoordinatedPlayback = false
        coordinatedPlaybackIdentifier = nil
        guard continueLocally else { return }
        if intendedRate > 0 {
            playbackRate = intendedRate
            engine.setRate(intendedRate)
            engine.play()
        } else {
            engine.pause()
        }
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
                isForced: track.isForced,
                isHearingImpaired: track.isHearingImpaired,
                isCommentary: track.isCommentary,
                isExternal: track.isExternal,
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
                isForced: track.isForced,
                isHearingImpaired: track.isHearingImpaired,
                isCommentary: track.isCommentary,
                isExternal: track.isExternal,
                isSelected: selectedSubtitleTrackID == track.id,
            )
        }

        return audio + subtitles
    }

    func stop() {
        resetScrubPreviewSession()
        isStopping = true
        isPaused = true
        isBuffering = false
        sourceVideoSize = nil
        engine.stop()
    }

    private func isCurrentScrubBucket(generation: Int, bucket: Int) -> Bool {
        isScrubPreviewing
            && scrubPreviewGeneration == generation
            && activeScrubBucket == bucket
    }

    private func requestBucketThumbnails(
        target: Double,
        bucket: Int,
        generation: Int,
    ) {
        if let scrubBIFProvider {
            scrubBIFTask = Task { @MainActor [weak self, scrubBIFProvider] in
                let thumbnail = await scrubBIFProvider.thumbnail(at: target)
                guard let self,
                      let thumbnail,
                      isCurrentScrubBucket(generation: generation, bucket: bucket)
                else {
                    return
                }
                scrubPreview = PlayerScrubPreview(
                    position: scrubPreview?.position ?? target,
                    image: thumbnail.image,
                )
                cancelPendingExtractorFallback()
            }
        }

        let bucketPosition = Double(bucket) * scrubBucketDuration
        scrubAetherTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await engine.scrubThumbnail(
                atSeconds: bucketPosition,
                maxWidth: scrubThumbnailWidth,
            )
            guard let image,
                  isCurrentScrubBucket(generation: generation, bucket: bucket),
                  scrubPreview?.image == nil
            else {
                return
            }
            scrubPreview = PlayerScrubPreview(
                position: scrubPreview?.position ?? target,
                image: image,
            )
            cancelPendingExtractorFallback()
        }
    }

    private func scheduleExtractorFallback(
        target: Double,
        targetGeneration: Int,
    ) {
        scrubExtractorDwellTask?.cancel()
        scrubExtractorDwellTask = nil
        guard scrubPreview?.image == nil, !engine.isLive else { return }

        scrubExtractorDwellTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: extractorThumbnailDelay)
            } catch {
                return
            }
            guard isScrubPreviewing,
                  scrubTargetGeneration == targetGeneration,
                  scrubPreview?.position == target,
                  scrubPreview?.image == nil,
                  !engine.isLive
            else {
                return
            }

            let extractor: FrameExtractor
            if let scrubFrameExtractor {
                extractor = scrubFrameExtractor
            } else {
                guard let newExtractor = engine.makeFrameExtractor() else { return }
                scrubFrameExtractor = newExtractor
                extractor = newExtractor
            }

            scrubExtractorRequestGeneration = targetGeneration
            let extractedImage = await extractor.thumbnail(
                at: target,
                maxWidth: scrubThumbnailWidth,
            )
            if scrubExtractorRequestGeneration == targetGeneration {
                scrubExtractorRequestGeneration = nil
            }
            guard let extractedImage,
                  isScrubPreviewing,
                  scrubTargetGeneration == targetGeneration,
                  scrubPreview?.position == target,
                  scrubPreview?.image == nil
            else {
                return
            }
            scrubPreview = PlayerScrubPreview(
                position: target,
                image: extractedImage,
            )
        }
    }

    private func cancelPendingExtractorFallback() {
        scrubExtractorDwellTask?.cancel()
        scrubExtractorDwellTask = nil
        cancelInFlightScrubExtraction()
    }

    private func resetScrubPreviewSession() {
        isScrubPreviewing = false
        scrubPreviewGeneration &+= 1
        scrubTargetGeneration &+= 1
        activeScrubBucket = nil
        scrubBIFTask?.cancel()
        scrubBIFTask = nil
        scrubAetherTask?.cancel()
        scrubAetherTask = nil
        scrubExtractorDwellTask?.cancel()
        scrubExtractorDwellTask = nil
        scrubBIFPreparationTask?.cancel()
        scrubBIFPreparationTask = nil
        scrubPreview = nil
        scrubExtractorRequestGeneration = nil

        if let scrubBIFProvider {
            self.scrubBIFProvider = nil
            Task {
                await scrubBIFProvider.cancel()
            }
        }
        if let extractor = scrubFrameExtractor {
            scrubFrameExtractor = nil
            Task {
                await extractor.shutdown()
            }
        }
    }

    private func cancelInFlightScrubExtraction() {
        guard scrubExtractorRequestGeneration != nil,
              let extractor = scrubFrameExtractor
        else {
            return
        }
        scrubExtractorRequestGeneration = nil
        scrubFrameExtractor = nil
        Task {
            await extractor.shutdown()
        }
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
                guard let self else { return }
                self.isBuffering = isBuffering || engine.isWaitingForCoordinatedPlayback
            }
            .store(in: &cancellables)

        engine.$isWaitingForCoordinatedPlayback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isWaiting in
                guard let self else { return }
                isBuffering = engine.isBuffering || isWaiting
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
        case let .error(message):
            errorMessage = message
        case .ended:
            isPaused = false
            guard hasStartedPlayback, !isStopping else { return }
            hasStartedPlayback = false
            onPlaybackEnded?()
        case .idle:
            isPaused = isStopping
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

struct PlayerSurfaceView: View {
    let controller: PlayerController

    var body: some View {
        AetherPlayerSurface(engine: controller.engine)
    }
}
