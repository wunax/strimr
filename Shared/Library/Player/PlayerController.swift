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
    var isLive = false
    var liveEdgeTime = 0.0
    var behindLiveSeconds = 0.0
    var seekableLiveRange: ClosedRange<Double>?
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
    private(set) var audioDelayMilliseconds = 0
    private(set) var subtitleDelayMilliseconds = 0
    private(set) var isApplyingAudioDelay = false
    private(set) var videoRoute: VideoRoute = .none
    private(set) var selectedSubtitleTrackID: Int?
    private(set) var volume: Float = 1.0
    private(set) var isCoordinatedPlayback = false

    var isMuted: Bool {
        volume == 0
    }

    /// Where subtitles are drawn from: the source time moved by the subtitle delay.
    var subtitlePosition: Double {
        sourcePosition - Double(subtitleDelayMilliseconds) / 1000
    }

    var audioDelayAvailability: PlaybackOffsetAvailability {
        .audio(
            isNativeBypass: videoRoute == .remoteBypass,
            isAudioOnly: videoRoute == .audio,
            isLiveWithoutDVR: isLive && !hasLiveDVRWindow && seekableLiveRange == nil,
        )
    }

    func subtitleDelayAvailability(burnsSubtitles: Bool) -> PlaybackOffsetAvailability {
        .subtitles(
            isNativeBypass: videoRoute == .remoteBypass,
            burnsSubtitles: burnsSubtitles,
            hasActiveSubtitleTrack: selectedSubtitleTrackID != nil,
        )
    }

    var assReloadSignal: PassthroughSubject<Void, Never> {
        assCoordinator.reloadSignal
    }

    @ObservationIgnored var onMediaLoaded: (() -> Void)?
    @ObservationIgnored var onPlaybackEnded: (() -> Void)?

    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var coordinatedPlaybackIdentifier: String?
    @ObservationIgnored private var hasStartedPlayback = false
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var playbackRate: Float = 1.0
    @ObservationIgnored private var styledASSSubtitles = true
    @ObservationIgnored private var mediaIdentifier = "media"
    @ObservationIgnored private var hasLiveDVRWindow = false
    @ObservationIgnored private var audioDelayDispatch = AudioDelayDispatch()
    @ObservationIgnored private var audioDelayDispatchTask: Task<Void, Never>?
    @ObservationIgnored private var audioDelayApplyPhase = AudioDelayApplyPhase.idle
    @ObservationIgnored private var audioDelayApplyTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var providerStreamIDsByFFIndex: [Int: Int] = [:]
    @ObservationIgnored private var externalSubtitleProviderStreamIDs: [Int: Int] = [:]
    @ObservationIgnored private var sidecarASSHeaderCancellable: AnyCancellable?
    @ObservationIgnored private lazy var assCoordinator = ASSRenderCoordinator(engine: engine)
    @ObservationIgnored private var lastAudibleVolume: Float = 1.0
    @ObservationIgnored private var volumeAttenuation: Float = 1.0
    @ObservationIgnored private var pendingSeekTarget: Double?
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
        isLive: Bool = false,
        nativeRemoteHLS: Bool = false,
        dvrWindowSeconds: TimeInterval? = nil,
        audioDelayMilliseconds: Int = 0,
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
        pendingSeekTarget = nil
        selectedSubtitleTrackID = nil
        subtitleCues = []
        sourceVideoSize = nil
        activeSubtitleCodec = nil
        self.styledASSSubtitles = styledASSSubtitles
        if mediaIdentifier != self.mediaIdentifier {
            setSubtitleDelay(milliseconds: 0)
        }
        self.mediaIdentifier = mediaIdentifier
        hasLiveDVRWindow = (dvrWindowSeconds ?? 0) > 0
        cancelPendingAudioDelay()
        self.audioDelayMilliseconds = PlaybackOffsetRange.audio.clamp(audioDelayMilliseconds)
        let audioDelaySeconds = PlaybackOffset(milliseconds: self.audioDelayMilliseconds).seconds
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
                        isLive: isLive,
                        dvrWindowSeconds: dvrWindowSeconds,
                        liveJoinProfile: .fastZap,
                        nativeRemoteHLS: nativeRemoteHLS,
                        preserveASSMarkup: true,
                        prepareNativeSubtitles: Self.preparesNativeSubtitles,
                        externalSubtitles: externalSubtitles.map(\.track),
                        autoplay: autoplay,
                        audioDelaySeconds: audioDelaySeconds,
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
                if isLive {
                    LiveTVErrorReporting.capture(error)
                } else {
                    ErrorReporter.capture(error)
                }
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

    func seekToLiveEdge() {
        Task { await engine.seekToLiveEdge() }
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

    /// Where relative seeks start from. `position` only catches up once the engine has taken the seek,
    /// so rapid presses would otherwise restart from the same stale value.
    var seekOrigin: Double {
        pendingSeekTarget ?? position
    }

    func seek(to time: Double) {
        if isCoordinatedPlayback {
            engine.playbackCoordinator.coordinateSeek(
                to: CMTime(seconds: time, preferredTimescale: 600),
                options: [],
            )
            return
        }
        pendingSeekTarget = time
        Task { @MainActor [weak self] in
            await self?.engine.seek(to: time)
        }
    }

    func seek(by delta: Double) {
        let target = max(0, seekOrigin + delta)
        guard !isLive, let duration else {
            seek(to: target)
            return
        }
        seek(to: min(target, duration))
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
        engine.volume = clampedVolume * volumeAttenuation
    }

    /// Scales the output without touching the user's volume, so a fade never shows up on the volume control.
    func setVolumeAttenuation(_ attenuation: Float) {
        volumeAttenuation = min(max(attenuation, 0), 1)
        engine.volume = volume * volumeAttenuation
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

    /// Updates the value at once; the engine gets it after a quiet period, because each change
    /// re-anchors playback (a reload of about 0.3 s on the AVPlayer route).
    func setAudioDelay(milliseconds: Int) {
        let clamped = PlaybackOffsetRange.audio.clamp(milliseconds)
        guard clamped != audioDelayMilliseconds else { return }
        audioDelayMilliseconds = clamped
        audioDelayDispatch.submit(clamped, at: .now)
        audioDelayDispatchTask?.cancel()
        let delay = audioDelayDispatch.delay
        audioDelayDispatchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if let pending = audioDelayDispatch.takeIfDue(at: .now) {
                sendAudioDelay(pending)
            }
        }
    }

    /// Sends a pending audio delay without waiting, when the sync bar closes.
    func commitAudioDelay() {
        audioDelayDispatchTask?.cancel()
        audioDelayDispatchTask = nil
        if let pending = audioDelayDispatch.flush() {
            sendAudioDelay(pending)
        }
    }

    func setSubtitleDelay(milliseconds: Int) {
        let clamped = PlaybackOffsetRange.subtitles.clamp(milliseconds)
        guard clamped != subtitleDelayMilliseconds else { return }
        subtitleDelayMilliseconds = clamped
        assCoordinator.setSubtitleDelay(seconds: PlaybackOffset(milliseconds: clamped).seconds)
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
        pendingSeekTarget = nil
        isPaused = true
        isBuffering = false
        sourceVideoSize = nil
        activeSubtitleCodec = nil
        selectedSubtitleTrackID = nil
        cancelPendingAudioDelay()
        engine.stop()
    }

    private func sendAudioDelay(_ milliseconds: Int) {
        let reanchors = (videoRoute == .loopback || videoRoute == .software)
            && (engine.state == .playing || engine.state == .paused)
        engine.setAudioDelay(PlaybackOffset(milliseconds: milliseconds).seconds)
        guard reanchors else { return }
        beginApplyingAudioDelay()
    }

    private func beginApplyingAudioDelay() {
        audioDelayApplyPhase = .requested
        isApplyingAudioDelay = true
        audioDelayApplyTimeoutTask?.cancel()
        audioDelayApplyTimeoutTask = Task { @MainActor [weak self] in
            // A re-anchor that never leaves the playing state (or hangs) must not leave the label up.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            if audioDelayApplyPhase == .requested {
                endApplyingAudioDelay()
                return
            }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            endApplyingAudioDelay()
        }
    }

    private func updateAudioDelayApplyPhase() {
        guard audioDelayApplyPhase != .idle else { return }
        let isSettled = !engine.isSeeking && (engine.state == .playing || engine.state == .paused)
        switch audioDelayApplyPhase {
        case .requested where !isSettled:
            audioDelayApplyPhase = .reanchoring
        case .reanchoring where isSettled:
            endApplyingAudioDelay()
        default:
            break
        }
    }

    private func endApplyingAudioDelay() {
        audioDelayApplyTimeoutTask?.cancel()
        audioDelayApplyTimeoutTask = nil
        audioDelayApplyPhase = .idle
        isApplyingAudioDelay = false
    }

    private func cancelPendingAudioDelay() {
        audioDelayDispatchTask?.cancel()
        audioDelayDispatchTask = nil
        _ = audioDelayDispatch.flush()
        endApplyingAudioDelay()
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
                self?.updateAudioDelayApplyPhase()
            }
            .store(in: &cancellables)

        engine.$isSeeking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAudioDelayApplyPhase()
            }
            .store(in: &cancellables)

        engine.$videoRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.videoRoute = $0 }
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

        engine.seekEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event.outcome {
                case .landed, .stalled, .rejected:
                    self?.pendingSeekTarget = nil
                case .began, .superseded:
                    break
                }
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

        engine.$isLive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isLive = $0 }
            .store(in: &cancellables)

        engine.clock.$liveEdgeTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.liveEdgeTime = $0 }
            .store(in: &cancellables)

        engine.clock.$behindLiveSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.behindLiveSeconds = $0 }
            .store(in: &cancellables)

        engine.clock.$seekableLiveRange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.seekableLiveRange = $0 }
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

private enum AudioDelayApplyPhase {
    case idle
    case requested
    case reanchoring
}

struct ExternalSubtitleTrackMappingError: LocalizedError {
    var errorDescription: String? {
        "AetherEngine returned an unexpected external subtitle track table."
    }
}

struct ExternalSubtitleRegistrationError: LocalizedError {
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
