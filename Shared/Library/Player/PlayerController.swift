import AetherEngine
import AVFoundation
import Combine
import CoreGraphics
import Foundation
import Observation
import SwiftAssRenderer
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
    var assRenderer: AssSubtitlesRenderer?
    var activeSubtitleCodec: String?
    var errorMessage: String?
    #if os(iOS) || os(macOS)
        var showsPictureInPictureControl = false
        var isPictureInPictureAvailable = false
        var isPictureInPictureActive = false
        var isPictureInPictureTransitioning = false
        @ObservationIgnored var onPictureInPictureStartFailed: (() -> Void)?
        @ObservationIgnored var onPictureInPictureRestoreRequested: (() -> Void)?
    #endif
    private(set) var scrubPreview: PlayerScrubPreview?
    private(set) var volume: Float = 1.0
    private(set) var isCoordinatedPlayback = false

    var isMuted: Bool {
        volume == 0
    }

    var assReloadSignal: PassthroughSubject<Void, Never> {
        assCoordinator.reloadSignal
    }

    @ObservationIgnored var onMediaLoaded: (() -> Void)?
    @ObservationIgnored var onPlaybackEnded: (() -> Void)?

    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var coordinatedPlaybackIdentifier: String?
    @ObservationIgnored private var selectedSubtitleTrackID: Int?
    @ObservationIgnored private var hasStartedPlayback = false
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var playbackRate: Float = 1.0
    @ObservationIgnored private var styledASSSubtitles = true
    @ObservationIgnored private var mediaIdentifier = "media"
    @ObservationIgnored private var providerStreamIDsByFFIndex: [Int: Int] = [:]
    @ObservationIgnored private var externalSubtitleProviderStreamIDs: [Int: Int] = [:]
    @ObservationIgnored private var sidecarASSHeaderCancellable: AnyCancellable?
    @ObservationIgnored private lazy var assCoordinator = ASSRenderCoordinator(engine: engine)
    @ObservationIgnored private var lastAudibleVolume: Float = 1.0
    @ObservationIgnored private var scrubThumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var scrubAetherTask: Task<Void, Never>?
    @ObservationIgnored private var scrubExtractorDwellTask: Task<Void, Never>?
    @ObservationIgnored private var scrubThumbnailPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var scrubThumbnailProvider: (any ScrubThumbnailProviding)?
    @ObservationIgnored private var scrubFrameExtractor: FrameExtractor?
    @ObservationIgnored private var scrubExtractorRequestGeneration: Int?
    @ObservationIgnored private var scrubGeneratedThumbnailCache: [Int: CGImage] = [:]
    @ObservationIgnored private var scrubGeneratedThumbnailOrder: [Int] = []
    @ObservationIgnored private var scrubPreviewGeneration = 0
    @ObservationIgnored private var activeScrubBucket: Int?
    @ObservationIgnored private var isScrubPreviewing = false
    @ObservationIgnored private var showsScrubThumbnailPreviews = true
    @ObservationIgnored private var generatesMissingScrubThumbnailPreviews = true
    #if os(iOS) || os(macOS)
        @ObservationIgnored private lazy var pictureInPictureCoordinator = PictureInPictureCoordinator(engine: engine)
    #endif

    private let scrubBucketDuration = 10.0
    private let unavailableThumbnailExtractorDelay: Duration = .milliseconds(250)
    private let failedThumbnailExtractorDelay: Duration = .milliseconds(450)
    private let pendingThumbnailExtractorDelay: Duration = .milliseconds(800)
    private let extractorAvailabilityPollInterval: Duration = .milliseconds(50)
    private let scrubThumbnailWidth = 320
    private let scrubGeneratedThumbnailCacheLimit = 32

    init() {
        do {
            engine = try AetherEngine()
        } catch {
            fatalError("Failed to initialize player engine: \(error)")
        }

        observeEngine()
        #if os(iOS) || os(macOS)
            configurePictureInPicture()
        #endif
    }

    func load(
        url: URL,
        httpHeaders: [String: String] = [:],
        startPosition: Double?,
        preferredAudioTrackID: Int?,
        losslessAudio: Bool,
        styledASSSubtitles: Bool,
        mediaIdentifier: String,
        providerStreamIDsByFFIndex: [Int: Int],
        externalSubtitles: [PlayerExternalSubtitle],
        scrubThumbnailSource: ScrubThumbnailSource? = nil,
        showsScrubThumbnailPreviews: Bool = true,
        generatesMissingScrubThumbnailPreviews: Bool = true,
        autoplay: Bool = true,
    ) {
        deactivateASSRendering()
        resetScrubPreviewSession()
        self.showsScrubThumbnailPreviews = showsScrubThumbnailPreviews
        self.generatesMissingScrubThumbnailPreviews = generatesMissingScrubThumbnailPreviews
        if showsScrubThumbnailPreviews {
            scrubThumbnailProvider = scrubThumbnailSource.map { source in
                switch source {
                case let .plex(source):
                    PlexBIFThumbnailProvider(source: source)
                case let .jellyfin(source):
                    JellyfinTrickplayThumbnailProvider(source: source)
                }
            }
        }
        isStopping = false
        hasStartedPlayback = false
        selectedSubtitleTrackID = nil
        subtitleCues = []
        sourceVideoSize = nil
        activeSubtitleCodec = nil
        self.styledASSSubtitles = styledASSSubtitles
        self.mediaIdentifier = mediaIdentifier
        self.providerStreamIDsByFFIndex = providerStreamIDsByFFIndex
        externalSubtitleProviderStreamIDs = [:]
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let sourceProbe = try await engine.load(
                    url: url,
                    startPosition: startPosition,
                    options: LoadOptions(
                        httpHeaders: httpHeaders,
                        audioBridgeMode: losslessAudio ? .lossless : .surroundCompat,
                        preserveASSMarkup: true,
                        prepareNativeSubtitles: Self.preparesNativeSubtitles,
                        externalSubtitles: externalSubtitles.map(\.track),
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
                let externalEngineTracks = engine.subtitleTracks.filter(\.isExternal)
                if externalEngineTracks.count == externalSubtitles.count {
                    externalSubtitleProviderStreamIDs = Dictionary(
                        uniqueKeysWithValues: zip(externalEngineTracks, externalSubtitles).map {
                            ($0.id, $1.providerStreamID)
                        },
                    )
                } else {
                    ErrorReporter.capture(ExternalSubtitleTrackMappingError())
                }
                if !isCoordinatedPlayback {
                    engine.setRate(playbackRate)
                }
                if !engine.isLive, let scrubThumbnailProvider {
                    scrubThumbnailPreparationTask = Task {
                        await scrubThumbnailProvider.prepare()
                    }
                }
                onMediaLoaded?()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                deactivateASSRendering()
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
        guard showsScrubThumbnailPreviews else { return }
        isScrubPreviewing = true
        updateScrubPreview(to: position)
    }

    func updateScrubPreview(to position: Double) {
        guard showsScrubThumbnailPreviews, isScrubPreviewing, position.isFinite else { return }

        let target = max(0, position)
        let bucket = Int(floor(target / scrubBucketDuration))
        let bucketChanged = activeScrubBucket != bucket

        if bucketChanged {
            cancelPendingExtractorFallback()
            activeScrubBucket = bucket
            scrubPreviewGeneration &+= 1
            scrubThumbnailTask?.cancel()
            scrubAetherTask?.cancel()
            scrubPreview = PlayerScrubPreview(
                position: target,
                image: scrubGeneratedThumbnailCache[bucket],
            )
            requestBucketThumbnails(
                target: target,
                bucket: bucket,
                generation: scrubPreviewGeneration,
            )
            scheduleExtractorFallback(
                bucket: bucket,
                generation: scrubPreviewGeneration,
            )
        } else {
            scrubPreview = PlayerScrubPreview(
                position: target,
                image: scrubPreview?.image,
            )
        }
    }

    func endScrubPreviewing() {
        isScrubPreviewing = false
        scrubPreviewGeneration &+= 1
        activeScrubBucket = nil
        scrubThumbnailTask?.cancel()
        scrubThumbnailTask = nil
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

    func selectSubtitleTrack(id: Int?, styledASSSubtitles: Bool? = nil) {
        deactivateASSRendering()
        if let styledASSSubtitles {
            self.styledASSSubtitles = styledASSSubtitles
        }
        selectedSubtitleTrackID = id
        guard let id else {
            engine.clearSubtitle()
            subtitleCues = []
            activeSubtitleCodec = nil
            return
        }

        let track = engine.subtitleTracks.first { $0.id == id }
        activeSubtitleCodec = track?.codec.lowercased()
        engine.selectSubtitleTrack(index: id)
        subtitleCues = engine.subtitleCues

        guard self.styledASSSubtitles,
              activeSubtitleCodec == "ass" || activeSubtitleCodec == "ssa"
        else {
            return
        }

        assCoordinator.onRendererChanged = { [weak self] renderer in
            self?.assRenderer = renderer
        }
        if track?.isExternal == true {
            sidecarASSHeaderCancellable = engine.$sidecarASSHeader
                .receive(on: DispatchQueue.main)
                .compactMap(\.self)
                .first()
                .sink { [weak self] header in
                    guard let self else { return }
                    assCoordinator.activate(header: header, mediaIdentifier: mediaIdentifier)
                    assRenderer = assCoordinator.renderer
                }
        } else {
            assCoordinator.activate(header: track?.assHeader, mediaIdentifier: mediaIdentifier)
            assRenderer = assCoordinator.renderer
        }
    }

    func registerExternalSubtitleIfNeeded(
        _ subtitle: PlayerExternalSubtitle,
        styledASSSubtitles: Bool,
    ) throws -> Int {
        if let existingID = externalSubtitleProviderStreamIDs.first(where: {
            $0.value == subtitle.providerStreamID
        })?.key {
            selectSubtitleTrack(id: existingID, styledASSSubtitles: styledASSSubtitles)
            return existingID
        }

        let track = engine.addExternalSubtitleTrack(subtitle.track)
        guard engine.subtitleTracks.contains(where: { $0.id == track.id && $0.isExternal }) else {
            throw ExternalSubtitleRegistrationError()
        }
        externalSubtitleProviderStreamIDs[track.id] = subtitle.providerStreamID
        selectSubtitleTrack(id: track.id, styledASSSubtitles: styledASSSubtitles)
        return track.id
    }

    func trackList() -> [PlayerTrack] {
        let audio = engine.audioTracks.map { track in
            PlayerTrack(
                id: track.id,
                ffIndex: track.id,
                providerStreamID: providerStreamIDsByFFIndex[track.id],
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
                ffIndex: track.isExternal ? nil : track.id,
                providerStreamID: track.isExternal
                    ? externalSubtitleProviderStreamIDs[track.id]
                    : providerStreamIDsByFFIndex[track.id],
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
        #if os(iOS) || os(macOS)
            pictureInPictureCoordinator.stop()
        #endif
        deactivateASSRendering()
        resetScrubPreviewSession()
        isStopping = true
        isPaused = true
        isBuffering = false
        sourceVideoSize = nil
        activeSubtitleCodec = nil
        selectedSubtitleTrackID = nil
        engine.stop()
    }

    #if os(iOS) || os(macOS)
        func startPictureInPicture() {
            pictureInPictureCoordinator.start()
        }

        private func configurePictureInPicture() {
            pictureInPictureCoordinator.onAvailabilityChanged = { [weak self] showsControl, isAvailable in
                self?.showsPictureInPictureControl = showsControl
                self?.isPictureInPictureAvailable = isAvailable
            }
            pictureInPictureCoordinator.onActivityChanged = { [weak self] isActive, isTransitioning in
                self?.isPictureInPictureActive = isActive
                self?.isPictureInPictureTransitioning = isTransitioning
            }
            pictureInPictureCoordinator.onRestoreUserInterface = { [weak self] in
                self?.onPictureInPictureRestoreRequested?()
            }
            pictureInPictureCoordinator.onStartFailed = { [weak self] in
                self?.onPictureInPictureStartFailed?()
            }
        }
    #endif

    private func deactivateASSRendering() {
        sidecarASSHeaderCancellable?.cancel()
        sidecarASSHeaderCancellable = nil
        assCoordinator.deactivate()
        assRenderer = nil
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
        if let scrubThumbnailProvider {
            scrubThumbnailTask = Task { @MainActor [weak self, scrubThumbnailProvider] in
                let thumbnail = await scrubThumbnailProvider.thumbnail(at: target)
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
            guard let self, scrubPreview?.image == nil else { return }
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
        bucket: Int,
        generation: Int,
    ) {
        scrubExtractorDwellTask?.cancel()
        scrubExtractorDwellTask = nil
        guard generatesMissingScrubThumbnailPreviews,
              scrubPreview?.image == nil,
              !engine.isLive
        else {
            return
        }

        scrubExtractorDwellTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = ContinuousClock.now
            while true {
                do {
                    try await Task.sleep(for: extractorAvailabilityPollInterval)
                } catch {
                    return
                }
                let requiredDelay = await extractorDelayForCurrentThumbnailState()
                if startedAt.duration(to: ContinuousClock.now) >= requiredDelay {
                    break
                }
            }
            guard isCurrentScrubBucket(generation: generation, bucket: bucket),
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

            let bucketPosition = Double(bucket) * scrubBucketDuration
            scrubExtractorRequestGeneration = generation
            let extractedImage = await extractor.thumbnail(
                at: bucketPosition,
                maxWidth: scrubThumbnailWidth,
            )
            if scrubExtractorRequestGeneration == generation {
                scrubExtractorRequestGeneration = nil
            }
            guard let extractedImage,
                  isCurrentScrubBucket(generation: generation, bucket: bucket),
                  scrubPreview?.image == nil
            else {
                return
            }
            storeGeneratedThumbnail(extractedImage, for: bucket)
            scrubPreview = PlayerScrubPreview(
                position: scrubPreview?.position ?? bucketPosition,
                image: extractedImage,
            )
        }
    }

    private func extractorDelayForCurrentThumbnailState() async -> Duration {
        guard let scrubThumbnailProvider else {
            return unavailableThumbnailExtractorDelay
        }
        switch await scrubThumbnailProvider.availability() {
        case .unavailable:
            return unavailableThumbnailExtractorDelay
        case .temporarilyFailed:
            return failedThumbnailExtractorDelay
        case .loading, .ready:
            return pendingThumbnailExtractorDelay
        }
    }

    private func cancelPendingExtractorFallback() {
        scrubExtractorDwellTask?.cancel()
        scrubExtractorDwellTask = nil
        cancelInFlightScrubExtraction()
    }

    private func storeGeneratedThumbnail(_ image: CGImage, for bucket: Int) {
        if scrubGeneratedThumbnailCache[bucket] == nil {
            scrubGeneratedThumbnailOrder.append(bucket)
        }
        scrubGeneratedThumbnailCache[bucket] = image

        while scrubGeneratedThumbnailOrder.count > scrubGeneratedThumbnailCacheLimit {
            let expiredBucket = scrubGeneratedThumbnailOrder.removeFirst()
            scrubGeneratedThumbnailCache[expiredBucket] = nil
        }
    }

    private func resetScrubPreviewSession() {
        isScrubPreviewing = false
        scrubPreviewGeneration &+= 1
        activeScrubBucket = nil
        scrubThumbnailTask?.cancel()
        scrubThumbnailTask = nil
        scrubAetherTask?.cancel()
        scrubAetherTask = nil
        scrubExtractorDwellTask?.cancel()
        scrubExtractorDwellTask = nil
        scrubThumbnailPreparationTask?.cancel()
        scrubThumbnailPreparationTask = nil
        scrubPreview = nil
        scrubExtractorRequestGeneration = nil
        scrubGeneratedThumbnailCache = [:]
        scrubGeneratedThumbnailOrder = []

        if let scrubThumbnailProvider {
            self.scrubThumbnailProvider = nil
            Task {
                await scrubThumbnailProvider.cancel()
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
            deactivateASSRendering()
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

    private static var preparesNativeSubtitles: Bool {
        #if os(iOS) || os(macOS)
            true
        #else
            false
        #endif
    }
}

private struct ExternalSubtitleTrackMappingError: LocalizedError {
    var errorDescription: String? {
        "AetherEngine returned an unexpected external subtitle track table."
    }
}

private struct ExternalSubtitleRegistrationError: LocalizedError {
    var errorDescription: String? {
        String(localized: "subtitles.search.activation.error")
    }
}

struct PlayerSurfaceView: View {
    let controller: PlayerController

    var body: some View {
        AetherPlayerSurface(engine: controller.engine)
    }
}
