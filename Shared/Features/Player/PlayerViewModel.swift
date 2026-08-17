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

    var subtitleSearchTitlePlaceholder: String {
        media?.title ?? ""
    }

    var usesCommonPlaybackQueue: Bool {
        mediaServices != nil
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
    @ObservationIgnored private var automaticSkipMarkerInFlight: SkipSegment?

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
        media = currentMedia
    }

    init(localMedia: MediaItem, localPlaybackURL: URL) {
        ratingKey = localMedia.id
        mediaServices = nil
        mediaQueue = nil
        shouldResumeFromOffsetFlag = false
        self.localMedia = localMedia
        self.localPlaybackURL = localPlaybackURL
        media = localMedia
        playbackURL = localPlaybackURL
    }

    func chapter(at time: Double) -> MediaChapter? {
        chapters.first { $0.contains(time: time) }
    }

    func chapterImageURL(
        for chapter: MediaChapter,
        width: Int,
        height: Int,
    ) -> URL? {
        guard let thumb = chapter.thumbPath else { return nil }
        return mediaServices?.artwork.artworkURL(path: thumb, width: width, height: height)
    }

    func trackMetadata(forID id: Int?) -> MediaTrackMetadata? {
        guard let id,
              let track = playbackPlan?.tracks.first(where: {
                  $0.sourceIndex == id || Int($0.id) == id
              })
        else { return nil }

        return MediaTrackMetadata(
            id: Int(track.id) ?? track.sourceIndex,
            sourceIndex: track.sourceIndex,
            codec: track.codec ?? "",
            title: track.title,
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
            $0.sourceIndex == id || Int($0.id) == id
        })?.sourceIndex ?? id
    }

    func providerStreamIDsByFFIndex() -> [Int: Int] {
        playbackPlan?.tracks.reduce(into: [:]) { result, track in
            result[track.sourceIndex] = Int(track.id) ?? track.sourceIndex
        } ?? [:]
    }

    func externalSubtitleTracks() -> [PlayerExternalSubtitle] {
        guard let playbackPlan else { return [] }
        let subtitleTracks = playbackPlan.tracks.filter { $0.kind == .subtitle }
        return playbackPlan.externalSubtitles.enumerated().map { index, track in
            let streamID = subtitleTracks.indices.contains(index)
                ? (Int(subtitleTracks[index].id) ?? subtitleTracks[index].sourceIndex)
                : -(index + 1)
            return PlayerExternalSubtitle(track: track, providerStreamID: streamID)
        }
    }

    func nextCommonPlayerViewModel() -> PlayerViewModel? {
        guard var queue = mediaQueue,
              let mediaServices,
              queue.items.indices.contains(queue.currentIndex + 1)
        else { return nil }

        queue.currentIndex += 1
        return PlayerViewModel(
            queue: queue,
            services: mediaServices,
            shouldResumeFromOffset: false,
        )
    }

    func load() async {
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
            let plan = try await mediaServices.playback.prepare(
                media: media,
                resume: shouldResumeFromOffsetFlag,
            )
            apply(plan: plan)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            serverAccessRecoveryError = mediaServices.playback.serverAccessRecoveryError(from: error)
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
        }
    }

    func refreshPlaybackSource() async throws -> URL {
        if let localPlaybackURL {
            return localPlaybackURL
        }
        guard let mediaServices, let media else { throw PlayerPlaybackError.missingPlaybackURL }

        do {
            let plan = try await mediaServices.playback.prepare(
                media: media,
                resume: shouldResumeFromOffsetFlag,
            )
            apply(plan: plan)
            return plan.url
        } catch {
            throw translatedServerAccessError(error, using: mediaServices.playback)
        }
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
        guard let mediaServices, let playbackPlan else { return }
        Task {
            do {
                try await mediaServices.playback.reportStopped(plan: playbackPlan, position: position)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
            }
        }
    }

    func markPlaybackFinished() async {
        guard let mediaServices, let playbackPlan else { return }
        do {
            try await mediaServices.playback.reportStopped(
                plan: playbackPlan,
                position: media?.duration ?? duration ?? position,
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
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

    private func apply(plan: PlaybackPlan) {
        playbackPlan = plan
        media = plan.media
        playbackURL = plan.url
        playbackHTTPHeaders = plan.httpHeaders
        preferredAudioStreamFFIndex = plan.selectedAudioIndex
        preferredSubtitleStreamID = plan.selectedSubtitleIndex
        chapters = plan.chapters
        markers = plan.skipSegments
        scrubThumbnailSource = plan.scrubThumbnailSource
        serverAccessRecoveryError = nil
        errorMessage = nil
    }

    private func reportTimeline(state: TimelineState, force: Bool = false) {
        guard mediaServices != nil, playbackPlan != nil else { return }
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
