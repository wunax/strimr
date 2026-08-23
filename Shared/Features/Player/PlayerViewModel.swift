import AetherEngine
import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    var media: MediaItem?
    var isLoading = false
    var errorMessage: String?
    var isBuffering = false
    var duration: Double?
    var position = 0.0
    var bufferedAhead = 0.0
    var playbackURL: URL?
    var playbackHTTPHeaders: [String: String] = [:]
    var serverAccessRecoveryError: MediaServerAccessRecoveryError?
    private(set) var scrubThumbnailSource: ScrubThumbnailSource?
    var isPaused = false
    var preferredAudioStreamFFIndex: Int?
    var preferredSubtitleStreamID: Int?
    var terminationMessage: String?
    var selectedQuality: TranscodeQualityPreset = .original
    var qualityFallbackMessage: String?
    var isLivePlayback: Bool { liveContext != nil }
    var liveChannel: LiveTVChannel? { liveContext?.channel }
    var liveProgram: LiveTVProgram?
    var liveCaptureRange: LiveTVCaptureRange?
    var liveNativeRemoteHLS = false
    var liveDVRWindowSeconds: TimeInterval? { liveCaptureRange?.duration }
    var canSwitchToPreviousLiveChannel: Bool {
        guard let liveContext else { return false }
        return liveContext.selectedIndex > 0
    }
    var canSwitchToNextLiveChannel: Bool {
        guard let liveContext else { return false }
        return liveContext.selectedIndex + 1 < liveContext.channels.count
    }

    var isTranscoding: Bool {
        playbackPlan?.method == .transcode
    }

    var resumePosition: Double? {
        media?.viewOffset
    }

    var markers: [SkipSegment] = []
    var chapters: [MediaChapter] = []

    var activeSkipMarker: SkipSegment? {
        activeMarker(where: \.isIntro) ?? activeMarker(where: \.isCredits)
    }

    var hasNavigableChapters: Bool {
        chapters.count >= 2
    }

    var canSearchSubtitles: Bool {
        !isLocalPlayback
            && !currentRatingKey.isEmpty
            && mediaServices?.detail.supportsRemoteSubtitleSearch == true
            && mediaServices?.authorization.canManageSubtitles == true
    }

    var subtitleSearchServices: MediaServices? {
        mediaServices
    }

    var artworkServices: MediaServices? {
        mediaServices
    }

    var subtitleSearchTitlePlaceholder: String {
        media?.title ?? ""
    }

    var usesCommonPlaybackQueue: Bool {
        mediaServices != nil && !isLivePlayback
    }

    var queueItems: [PlaybackQueueItem] {
        mediaQueue?.items ?? []
    }

    var queueCurrentIndex: Int? {
        guard let mediaQueue,
              mediaQueue.items.indices.contains(mediaQueue.currentIndex)
        else { return nil }
        return mediaQueue.currentIndex
    }

    var hasNavigableQueue: Bool {
        queueItems.count > 1 && mediaServices != nil
    }

    var currentRatingKey: String {
        media?.id ?? ratingKey
    }

    var shouldResumeFromOffset: Bool {
        shouldResumeFromOffsetFlag
    }

    var serverAccessGeneration: Int {
        mediaServices?.playback.serverAccessGeneration ?? 0
    }

    var isLocalPlayback: Bool {
        localPlaybackURL != nil
    }

    @ObservationIgnored private let timelineInterval: TimeInterval = 10
    @ObservationIgnored private var lastTimelineSentAt: Date?
    @ObservationIgnored private var lastTimelineState: TimelineState?
    @ObservationIgnored private let ratingKey: String
    @ObservationIgnored private let mediaServices: MediaServices?
    @ObservationIgnored private var mediaQueue: PlaybackQueue?
    @ObservationIgnored private var playbackPlan: PlaybackPlan?
    @ObservationIgnored private var didReportPlaybackStarted = false
    @ObservationIgnored private let shouldResumeFromOffsetFlag: Bool
    @ObservationIgnored private let localMedia: MediaItem?
    @ObservationIgnored private let localPlaybackURL: URL?
    @ObservationIgnored private let localExternalSubtitles: [ExternalSubtitleTrack]
    @ObservationIgnored private var automaticSkipMarkerInFlight: SkipSegment?
    @ObservationIgnored private var liveContext: LiveTVLaunchContext?
    @ObservationIgnored private var liveSession: (any LiveTVPlaybackSession)?
    @ObservationIgnored private var isSwitchingLiveChannel = false
    @ObservationIgnored private var isLiveReportingSuspended = false
    @ObservationIgnored private var pendingLiveSessionToStop: (any LiveTVPlaybackSession)?

    init(
        queue: PlaybackQueue,
        services: MediaServices,
        shouldResumeFromOffset: Bool = true,
    ) {
        mediaQueue = queue
        mediaServices = services
        let currentMedia = queue.items.indices.contains(queue.currentIndex)
            ? queue.items[queue.currentIndex].media
            : queue.items.first?.media
        ratingKey = currentMedia?.id ?? ""
        shouldResumeFromOffsetFlag = shouldResumeFromOffset
        localMedia = nil
        localPlaybackURL = nil
        localExternalSubtitles = []
        media = currentMedia
    }

    init(
        localMedia: MediaItem,
        localPlaybackURL: URL,
        localExternalSubtitles: [ExternalSubtitleTrack] = [],
    ) {
        ratingKey = localMedia.id
        mediaServices = nil
        mediaQueue = nil
        shouldResumeFromOffsetFlag = false
        self.localMedia = localMedia
        self.localPlaybackURL = localPlaybackURL
        self.localExternalSubtitles = localExternalSubtitles
        media = localMedia
        playbackURL = localPlaybackURL
        selectedQuality = .original
    }

    init(live context: LiveTVLaunchContext, services: MediaServices) {
        liveContext = context
        mediaServices = services
        mediaQueue = nil
        ratingKey = context.channel.id
        shouldResumeFromOffsetFlag = false
        localMedia = nil
        localPlaybackURL = nil
        localExternalSubtitles = []
        media = Self.liveMedia(channel: context.channel, server: services.identity)
        selectedQuality = .original
    }

    func chapter(at time: Double) -> MediaChapter? {
        chapters.first { $0.contains(time: time) }
    }

    func trackMetadata(forID id: Int?) -> MediaTrackMetadata? {
        guard let id,
              let track = playbackPlan?.tracks.first(where: {
                  providerStreamID(for: $0) == id
              })
        else { return nil }

        return MediaTrackMetadata(
            id: Int(track.id) ?? track.sourceIndex,
            sourceIndex: track.sourceIndex,
            codec: track.codec ?? "",
            title: nil,
            displayTitle: track.title,
            language: track.language,
            isDefault: track.isDefault,
            isForced: track.isForced,
            isHearingImpaired: track.isHearingImpaired,
        )
    }

    func ffIndex(forProviderStreamID id: Int?) -> Int? {
        guard let id else { return nil }
        return playbackPlan?.tracks.first(where: {
            providerStreamID(for: $0) == id
        })?.sourceIndex ?? id
    }

    func providerStreamIDsByFFIndex() -> [Int: Int] {
        playbackPlan?.tracks.reduce(into: [:]) { result, track in
            result[track.sourceIndex] = providerStreamID(for: track)
        } ?? [:]
    }

    func externalSubtitleTracks() -> [PlayerExternalSubtitle] {
        if isLocalPlayback {
            return localExternalSubtitles.enumerated().map { index, track in
                PlayerExternalSubtitle(track: track, providerStreamID: -(index + 1))
            }
        }
        guard let playbackPlan else { return [] }
        let subtitleTracks = playbackPlan.tracks.filter {
            $0.kind == .subtitle && $0.isExternal
        }
        return playbackPlan.externalSubtitles.enumerated().map { index, track in
            let streamID = subtitleTracks.indices.contains(index)
                ? providerStreamID(for: subtitleTracks[index])
                : -(index + 1)
            return PlayerExternalSubtitle(track: track, providerStreamID: streamID)
        }
    }

    func sourcePlayerTracks() -> [PlayerTrack] {
        guard let playbackPlan else { return [] }
        return playbackPlan.tracks.map { track in
            let providerStreamID = providerStreamID(for: track)
            let isSelected = switch track.kind {
            case .audio:
                playbackPlan.selectedAudioIndex == track.sourceIndex
            case .subtitle:
                playbackPlan.selectedSubtitleIndex == providerStreamID
                    || playbackPlan.selectedSubtitleIndex == track.sourceIndex
            }
            return PlayerTrack(
                id: track.sourceIndex,
                ffIndex: track.sourceIndex,
                providerStreamID: providerStreamID,
                type: track.kind == .audio ? .audio : .subtitle,
                title: track.title,
                language: track.language,
                codec: track.codec,
                isDefault: track.isDefault,
                isForced: track.isForced,
                isHearingImpaired: track.isHearingImpaired,
                isCommentary: false,
                isExternal: track.isExternal,
                isSelected: isSelected,
            )
        }
    }

    private func providerStreamID(for track: PlaybackTrack) -> Int {
        Int(track.id) ?? track.sourceIndex
    }

    func makeNextPlayerViewModel() -> PlayerViewModel? {
        guard let queueCurrentIndex else { return nil }
        return makePlayerViewModel(
            at: queueCurrentIndex + 1,
            shouldResumeFromOffset: false,
        )
    }

    func makePlayerViewModel(
        at index: Int,
        shouldResumeFromOffset: Bool,
    ) -> PlayerViewModel? {
        guard var queue = mediaQueue,
              let mediaServices,
              queue.items.indices.contains(index)
        else { return nil }

        queue.currentIndex = index
        let viewModel = PlayerViewModel(
            queue: queue,
            services: mediaServices,
            shouldResumeFromOffset: shouldResumeFromOffset,
        )
        viewModel.selectedQuality = selectedQuality
        return viewModel
    }

    func load(quality: TranscodeQualityPreset? = nil) async {
        if let localPlaybackURL, let localMedia {
            media = localMedia
            playbackURL = localPlaybackURL
            errorMessage = nil
            return
        }

        guard let mediaServices, let media else {
            errorMessage = String(localized: "errors.selectServer.playMedia")
            return
        }

        isLoading = true
        errorMessage = nil
        resetPlaybackMetadata()
        defer { isLoading = false }

        do {
            if let liveContext {
                let session = try await mediaServices.liveTV.startPlayback(channel: liveContext.channel)
                let offset = liveContext.startsFromBeginning
                    ? session.captureRange.flatMap { range in
                        liveContext.program.map { max(0, $0.startDate.timeIntervalSince(range.startDate)) }
                    }
                    : nil
                let source = try await session.source(offsetFromCaptureStart: offset)
                liveSession = session
                apply(liveSource: source)
                liveProgram = source.program ?? liveContext.program
                return
            }
            if let quality {
                selectedQuality = quality
            }
            let plan = try await mediaServices.playback.prepare(
                media: media,
                resume: shouldResumeFromOffsetFlag,
                quality: selectedQuality,
            )
            apply(plan: plan)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            serverAccessRecoveryError = mediaServices.playback.serverAccessRecoveryError(from: error)
            if isLivePlayback {
                LiveTVErrorReporting.capture(error)
                errorMessage = String(localized: "livetv.playback.error")
            } else {
                ErrorReporter.capture(error)
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshPlaybackSource() async throws -> URL {
        if let localPlaybackURL {
            return localPlaybackURL
        }
        if let liveSession {
            let replacement = try await liveSession.recover()
            let source = try await replacement.source(offsetFromCaptureStart: nil)
            await liveSession.stop()
            self.liveSession = replacement
            apply(liveSource: source)
            return source.url
        }
        guard let mediaServices, let media else { throw PlayerPlaybackError.missingPlaybackURL }

        do {
            let previousPlan = playbackPlan
            let plan = try await mediaServices.playback.prepare(
                media: media,
                resume: shouldResumeFromOffsetFlag,
                quality: selectedQuality,
            )
            apply(plan: plan)
            if let previousPlan {
                await mediaServices.playback.release(plan: previousPlan)
            }
            return plan.url
        } catch {
            throw translatedServerAccessError(error, using: mediaServices.playback)
        }
    }

    func changeQuality(to quality: TranscodeQualityPreset, force: Bool = false) async throws -> URL {
        guard !isLivePlayback else { throw PlayerPlaybackError.missingPlaybackURL }
        guard !isLocalPlayback else { throw PlayerPlaybackError.missingPlaybackURL }
        guard let mediaServices, let media else { throw PlayerPlaybackError.missingPlaybackURL }
        if !force, quality == selectedQuality, let playbackURL {
            return playbackURL
        }

        let previousPlan = playbackPlan
        let plan = try await mediaServices.playback.prepare(
            media: media,
            resume: false,
            quality: quality,
        )
        selectedQuality = quality
        apply(plan: plan)
        if let previousPlan {
            await mediaServices.playback.release(plan: previousPlan)
        }
        return plan.url
    }

    func refreshMetadataAfterSubtitleAttachment() async throws -> PlayerExternalSubtitle {
        guard !isLocalPlayback,
              let mediaServices,
              let media
        else { throw PlayerPlaybackError.missingExternalSubtitle }

        let previousURLs = Set(playbackPlan?.externalSubtitles.map(\.url) ?? [])
        do {
            let refreshed = try await mediaServices.playback.externalSubtitles(media: media)
            guard let track = refreshed.first(where: { !previousURLs.contains($0.url) }) ?? refreshed.first else {
                throw PlayerPlaybackError.missingExternalSubtitle
            }
            return PlayerExternalSubtitle(track: track, providerStreamID: -(refreshed.count + 1))
        } catch {
            throw translatedServerAccessError(error, using: mediaServices.playback)
        }
    }

    @discardableResult
    func recoverServerAccessIfUnauthorized() async throws -> Bool {
        guard let mediaServices, !isLocalPlayback else { return false }
        return try await mediaServices.playback.recoverServerAccessIfUnauthorized()
    }

    func forceServerAccessRecovery() async throws {
        guard let mediaServices, !isLocalPlayback else { return }
        try await mediaServices.playback.forceServerAccessRecovery()
    }

    func clearServerAccessRecoveryError() {
        serverAccessRecoveryError = nil
    }

    func handlePlaybackState(isPaused: Bool, isBuffering: Bool) {
        let previousState = playbackState
        self.isPaused = isPaused
        self.isBuffering = isBuffering

        if previousState != playbackState {
            reportTimeline(state: playbackState, force: true)
        }
    }

    func handlePlaybackPosition(_ position: Double, isScrubbing: Bool) {
        guard !isScrubbing else { return }
        self.position = position
        reportTimeline(state: playbackState)
    }

    func handlePlaybackDuration(_ duration: Double?) {
        self.duration = duration
    }

    func handleBufferedAhead(_ bufferedAhead: Double) {
        self.bufferedAhead = bufferedAhead
    }

    func handleStop() {
        if let liveSession {
            self.liveSession = nil
            let pending = pendingLiveSessionToStop
            pendingLiveSessionToStop = nil
            Task {
                await liveSession.stop()
                await pending?.stop()
            }
            return
        }
        guard let mediaServices, let playbackPlan else { return }
        Task {
            do {
                try await mediaServices.playback.reportStopped(plan: playbackPlan, position: position)
            } catch {
                if !Task.isCancelled, !error.isCancellation {
                    ErrorReporter.capture(error)
                }
            }
            await mediaServices.playback.release(plan: playbackPlan)
        }
    }

    func enterLiveBackground() async -> Bool {
        isLiveReportingSuspended = true
        guard let liveSession, liveSession.backgroundPolicy == .stopAndExit else { return false }
        self.liveSession = nil
        await liveSession.stop()
        return true
    }

    func leaveLiveBackground() {
        isLiveReportingSuspended = false
    }

    func markPlaybackFinished() async {
        if let liveSession {
            self.liveSession = nil
            await liveSession.stop()
            return
        }
        guard let mediaServices, let playbackPlan else { return }
        do {
            try await mediaServices.playback.reportStopped(
                plan: playbackPlan,
                position: media?.duration ?? duration ?? position,
            )
        } catch {
            if !Task.isCancelled, !error.isCancellation {
                LiveTVErrorReporting.capture(error)
            }
        }
        await mediaServices.playback.release(plan: playbackPlan)
    }

    func automaticSkipMarker(
        autoSkipIntros: Bool,
        autoSkipCredits: Bool,
    ) -> SkipSegment? {
        if let automaticSkipMarkerInFlight {
            guard !automaticSkipMarkerInFlight.contains(time: position) else { return nil }
            self.automaticSkipMarkerInFlight = nil
        }

        guard let marker = markers.first(where: {
            $0.contains(time: position)
                && (($0.isIntro && autoSkipIntros) || ($0.isCredits && autoSkipCredits))
        }) else { return nil }

        automaticSkipMarkerInFlight = marker
        return marker
    }

    func persistStreamSelection(for track: PlayerTrack) async {
        guard let mediaServices,
              let itemID = media?.id,
              let streamID = track.providerStreamID
        else { return }

        do {
            switch track.type {
            case .audio:
                try await mediaServices.detail.selectAudioTrack(id: streamID, itemID: itemID)
            case .subtitle:
                try await mediaServices.detail.selectSubtitleTrack(id: streamID, itemID: itemID)
            case .video:
                break
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }

    func persistSubtitleStreamSelection(for track: PlayerTrack?) async {
        guard let mediaServices, let itemID = media?.id else { return }
        let streamID = track?.providerStreamID
        do {
            try await mediaServices.detail.selectSubtitleTrack(id: streamID, itemID: itemID)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }

    private var playbackState: TimelineState {
        if isBuffering {
            return .buffering
        }
        return isPaused ? .paused : .playing
    }

    private func activeMarker(where predicate: (SkipSegment) -> Bool) -> SkipSegment? {
        markers.first { predicate($0) && $0.contains(time: position) }
    }

    private func resetPlaybackMetadata() {
        preferredAudioStreamFFIndex = nil
        preferredSubtitleStreamID = nil
        scrubThumbnailSource = nil
        automaticSkipMarkerInFlight = nil
        markers = []
        chapters = []
    }

    func switchLiveChannel(by offset: Int) async throws -> URL {
        guard !isSwitchingLiveChannel, let context = liveContext, let mediaServices else {
            throw PlayerPlaybackError.missingPlaybackURL
        }
        let index = context.selectedIndex + offset
        guard context.channels.indices.contains(index) else { throw PlayerPlaybackError.missingPlaybackURL }
        isSwitchingLiveChannel = true
        defer { isSwitchingLiveChannel = false }

        let replacementContext = LiveTVLaunchContext(channels: context.channels, selectedIndex: index)
        let replacement = try await mediaServices.liveTV.startPlayback(channel: replacementContext.channel)
        do {
            let source = try await replacement.source(offsetFromCaptureStart: nil)
            let previous = liveSession
            liveContext = replacementContext
            liveSession = replacement
            pendingLiveSessionToStop = previous
            media = Self.liveMedia(channel: replacementContext.channel, server: mediaServices.identity)
            apply(liveSource: source)
            return source.url
        } catch {
            await replacement.stop()
            throw error
        }
    }

    func confirmLiveChannelSwitch() {
        guard let pendingLiveSessionToStop else { return }
        self.pendingLiveSessionToStop = nil
        Task { await pendingLiveSessionToStop.stop() }
    }

    private func apply(liveSource source: LiveTVPlaybackSource) {
        playbackURL = source.url
        playbackHTTPHeaders = source.httpHeaders
        liveProgram = source.program
        liveCaptureRange = source.captureRange
        liveNativeRemoteHLS = source.nativeRemoteHLS
        duration = source.captureRange?.duration
        markers = []
        chapters = []
        scrubThumbnailSource = nil
        errorMessage = nil
    }

    private func apply(plan: PlaybackPlan) {
        playbackPlan = plan
        media = plan.media
        playbackURL = plan.url
        playbackHTTPHeaders = plan.httpHeaders
        selectedQuality = plan.requestedQuality
        qualityFallbackMessage = plan.qualityFallbackMessage
        preferredAudioStreamFFIndex = plan.selectedAudioIndex
        preferredSubtitleStreamID = plan.selectedSubtitleIndex
        chapters = plan.chapters
        markers = plan.skipSegments
        scrubThumbnailSource = plan.scrubThumbnailSource
        serverAccessRecoveryError = nil
        errorMessage = nil
    }

    private func reportTimeline(state: TimelineState, force: Bool = false) {
        guard liveSession != nil || (mediaServices != nil && playbackPlan != nil) else { return }
        let now = Date()
        let stateChanged = lastTimelineState != state
        let intervalElapsed = lastTimelineSentAt.map {
            now.timeIntervalSince($0) >= timelineInterval
        } ?? true
        guard force || stateChanged || intervalElapsed else { return }

        lastTimelineSentAt = now
        lastTimelineState = state
        Task { await sendTimeline(state: state) }
    }

    private func sendTimeline(state: TimelineState) async {
        if let liveSession {
            guard !isLiveReportingSuspended else { return }
            do {
                liveCaptureRange = try await liveSession.report(position: position, isPaused: state == .paused)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
            }
            return
        }
        guard let mediaServices, let playbackPlan else { return }
        do {
            if didReportPlaybackStarted {
                try await mediaServices.playback.reportProgress(
                    plan: playbackPlan,
                    position: position,
                    isPaused: state == .paused,
                )
            } else {
                try await mediaServices.playback.reportStarted(
                    plan: playbackPlan,
                    position: position,
                    isPaused: state == .paused,
                )
                didReportPlaybackStarted = true
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            serverAccessRecoveryError = mediaServices.playback.serverAccessRecoveryError(from: error)
            ErrorReporter.capture(error)
        }
    }

    private static func liveMedia(channel: LiveTVChannel, server: ServerIdentity) -> MediaItem {
        MediaItem(
            id: channel.id, identity: MediaIdentity(server: server, itemID: channel.id),
            guid: "livetv://\(server.provider.rawValue)/channel", summary: nil,
            title: channel.displayTitle, type: .movie, parentRatingKey: nil,
            grandparentRatingKey: nil, genres: [], year: nil, duration: nil,
            videoResolution: channel.isHD ? "HD" : nil, rating: nil, ratings: [],
            contentRating: nil, studio: nil, tagline: nil, thumbPath: channel.thumbPath,
            artPath: channel.artPath, artworkCornerColors: nil, viewOffset: nil,
            viewCount: nil, childCount: nil, leafCount: nil, viewedLeafCount: nil,
            grandparentTitle: nil, parentTitle: nil, parentIndex: nil, index: nil,
            grandparentThumbPath: nil, grandparentArtPath: nil, parentThumbPath: nil,
        )
    }

    private func translatedServerAccessError(
        _ error: Error,
        using playback: any MediaPlaybackService,
    ) -> Error {
        playback.serverAccessRecoveryError(from: error) ?? error
    }
}

private enum TimelineState: Equatable {
    case buffering
    case paused
    case playing
}

private enum PlayerPlaybackError: LocalizedError {
    case missingPlaybackURL
    case missingExternalSubtitle

    var errorDescription: String? {
        switch self {
        case .missingPlaybackURL:
            String(localized: "errors.selectServer.playMedia")
        case .missingExternalSubtitle:
            String(localized: "subtitles.search.activation.error")
        }
    }
}
