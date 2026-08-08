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
    var serverAccessRecoveryError: PlexServerAccessRecoveryError?
    private(set) var scrubThumbnailSource: PlexBIFSource?
    var isPaused = false
    var preferredAudioStreamFFIndex: Int?
    var preferredSubtitleStreamID: Int?
    var resumePosition: Double? {
        media?.viewOffset
    }

    var markers: [PlexMarker] = []
    var chapters: [PlexChapter] = []
    var activeSkipMarker: PlexMarker? {
        activeMarker(where: \.isIntro)
            ?? activeMarker(where: \.isCredits)
    }

    var hasNavigableChapters: Bool {
        chapters.count >= 2
    }

    func chapter(at time: Double) -> PlexChapter? {
        chapters.first { $0.contains(time: time) }
    }

    func chapterImageURL(
        for chapter: PlexChapter,
        width: Int,
        height: Int,
    ) -> URL? {
        guard let thumb = chapter.thumb else { return nil }
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }
        return imageRepository.transcodeImageURL(
            path: thumb,
            width: width,
            height: height,
        )
    }

    @ObservationIgnored private let timelineInterval: TimeInterval = 10
    @ObservationIgnored private var lastTimelineSentAt: Date?
    @ObservationIgnored private var lastTimelineState: PlaybackRepository.PlaybackState?
    @ObservationIgnored private let ratingKey: String
    @ObservationIgnored private var playQueueState: PlayQueueState
    @ObservationIgnored private let context: PlexAPIContext
    var serverContext: PlexAPIContext {
        context
    }

    @ObservationIgnored private let shouldResumeFromOffsetFlag: Bool
    @ObservationIgnored private let localMedia: MediaItem?
    @ObservationIgnored private let localPlaybackURL: URL?
    @ObservationIgnored private let shouldReportPlaybackToServer: Bool
    @ObservationIgnored private var activePartId: Int?
    @ObservationIgnored private var activePartFile: String?
    @ObservationIgnored private var partStreams: [PlexPartStream] = []
    @ObservationIgnored private var streamsByFFIndex: [Int: PlexPartStream] = [:]
    @ObservationIgnored private var streamsByID: [Int: PlexPartStream] = [:]
    @ObservationIgnored private var automaticSkipMarkerInFlight: PlexMarker?
    @ObservationIgnored private let sessionIdentifier = UUID().uuidString
    @ObservationIgnored private var didReceiveTermination = false
    var terminationMessage: String?

    var canSearchSubtitles: Bool {
        !isLocalPlayback && activePartId != nil && !ratingKey.isEmpty
    }

    var subtitleSearchTitlePlaceholder: String {
        activePartFile.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? media?.title
            ?? ""
    }

    func plexStream(forID id: Int?) -> PlexPartStream? {
        guard let id else { return nil }
        return streamsByID[id]
    }

    func ffIndex(forPlexStreamID id: Int?) -> Int? {
        plexStream(forID: id)?.index
    }

    func plexStreamIDsByFFIndex() -> [Int: Int] {
        streamsByFFIndex.reduce(into: [:]) { result, entry in
            guard let id = entry.value.id else { return }
            result[entry.key] = id
        }
    }

    func externalSubtitleTracks() -> [PlayerExternalSubtitle] {
        guard let mediaRepository = try? MediaRepository(context: context) else { return [] }

        return partStreams
            .filter { $0.streamType == .subtitle && $0.key != nil }
            .compactMap { stream in
                guard let id = stream.id,
                      let key = stream.key,
                      let url = mediaRepository.mediaURL(path: key)
                else {
                    return nil
                }

                return PlayerExternalSubtitle(
                    track: ExternalSubtitleTrack(
                        url: url,
                        name: stream.title ?? stream.displayTitle,
                        language: stream.language,
                        isForced: stream.forced == true,
                        isHearingImpaired: stream.hearingImpaired == true,
                        formatHint: stream.codec,
                    ),
                    plexStreamID: id,
                )
            }
    }

    init(
        playQueue: PlayQueueState,
        ratingKey: String? = nil,
        context: PlexAPIContext,
        shouldResumeFromOffset: Bool = true,
    ) {
        playQueueState = playQueue
        self.ratingKey = ratingKey ?? playQueue.selectedRatingKey ?? ""
        self.context = context
        shouldResumeFromOffsetFlag = shouldResumeFromOffset
        localMedia = nil
        localPlaybackURL = nil
        shouldReportPlaybackToServer = true
    }

    init(localMedia: MediaItem, localPlaybackURL: URL, context: PlexAPIContext) {
        playQueueState = PlayQueueState(localRatingKey: localMedia.id)
        ratingKey = localMedia.id
        self.context = context
        shouldResumeFromOffsetFlag = false
        self.localMedia = localMedia
        self.localPlaybackURL = localPlaybackURL
        shouldReportPlaybackToServer = false
        media = localMedia
        playbackURL = localPlaybackURL
    }

    var playQueue: PlayQueueState {
        playQueueState
    }

    var currentRatingKey: String {
        ratingKey
    }

    var shouldResumeFromOffset: Bool {
        shouldResumeFromOffsetFlag
    }

    var serverAccessGeneration: Int {
        context.serverAccessGeneration
    }

    var isLocalPlayback: Bool {
        localPlaybackURL != nil
    }

    func load() async {
        if let localPlaybackURL, let localMedia {
            media = localMedia
            playbackURL = localPlaybackURL
            errorMessage = nil
            return
        }

        guard !ratingKey.isEmpty else {
            errorMessage = String(localized: "errors.selectServer.playMedia")
            return
        }

        guard let metadataRepository = try? MetadataRepository(context: context) else {
            errorMessage = String(localized: "errors.selectServer.playMedia")
            return
        }

        isLoading = true
        errorMessage = nil
        preferredAudioStreamFFIndex = nil
        preferredSubtitleStreamID = nil
        activePartId = nil
        activePartFile = nil
        scrubThumbnailSource = nil
        partStreams = []
        streamsByFFIndex = [:]
        streamsByID = [:]
        automaticSkipMarkerInFlight = nil
        markers = []
        chapters = []
        defer { isLoading = false }

        do {
            try await loadRemoteMetadata(using: metadataRepository)
        } catch {
            if let recoveryError = error as? PlexServerAccessRecoveryError {
                serverAccessRecoveryError = recoveryError
            }
            errorMessage = error.localizedDescription
        }
    }

    func refreshPlaybackSource() async throws -> URL {
        guard !isLocalPlayback else {
            guard let playbackURL else { throw PlexAPIError.invalidURL }
            return playbackURL
        }
        let repository = try MetadataRepository(context: context)
        try await loadRemoteMetadata(using: repository)
        guard let playbackURL else {
            throw PlexAPIError.invalidURL
        }
        return playbackURL
    }

    func refreshMetadataAfterSubtitleAttachment() async throws -> PlayerExternalSubtitle {
        guard !isLocalPlayback else { throw PlexSubtitleActivationError.missingSelectedExternalTrack }
        let repository = try MetadataRepository(context: context)
        try await loadRemoteMetadata(using: repository)
        guard let selectedID = preferredSubtitleStreamID,
              let subtitle = externalSubtitleTracks().first(where: { $0.plexStreamID == selectedID })
        else {
            throw PlexSubtitleActivationError.missingSelectedExternalTrack
        }
        return subtitle
    }

    @discardableResult
    func recoverServerAccessIfUnauthorized() async throws -> Bool {
        guard !isLocalPlayback else { return false }
        return try await context.validateCurrentServerAccess()
    }

    func forceServerAccessRecovery() async throws {
        guard !isLocalPlayback else { return }
        try await context.forceRefreshCurrentServerAccess()
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
        reportTimeline(state: .stopped, force: true)
    }

    func markPlaybackFinished() async {
        guard shouldReportPlaybackToServer else { return }
        let currentDuration = max(0, Int((media?.duration ?? duration ?? position) * 1000))

        do {
            let repository = try PlaybackRepository(context: context)
            _ = try await repository.updateTimeline(
                ratingKey: ratingKey,
                state: .stopped,
                time: currentDuration,
                duration: currentDuration,
                sessionIdentifier: sessionIdentifier,
                playQueueItemID: currentPlayQueueItemID(),
            )
        } catch {
            debugPrint("Failed to mark playback as finished:", error)
        }
    }

    func nextItemInQueue() async -> PlexItem? {
        guard shouldReportPlaybackToServer else { return nil }
        await refreshPlayQueue()
        let fallbackRatingKey = ratingKey.isEmpty ? nil : ratingKey
        guard let currentRatingKey = media?.id ?? fallbackRatingKey else { return nil }
        return playQueueState.item(after: currentRatingKey)
    }

    private var playbackState: PlaybackRepository.PlaybackState {
        if isBuffering {
            return .buffering
        }
        return isPaused ? .paused : .playing
    }

    private func reportTimeline(
        state: PlaybackRepository.PlaybackState,
        force: Bool = false,
    ) {
        guard shouldReportPlaybackToServer else { return }
        guard !didReceiveTermination else { return }
        let now = Date()
        let stateChanged = lastTimelineState != state
        let shouldSend = force || stateChanged || lastTimelineSentAt
            .map { now.timeIntervalSince($0) >= timelineInterval } ?? true

        guard shouldSend else { return }

        lastTimelineSentAt = now
        lastTimelineState = state

        Task {
            await sendTimeline(state: state)
        }
    }

    private func sendTimeline(state: PlaybackRepository.PlaybackState) async {
        guard shouldReportPlaybackToServer else { return }
        let currentTime = max(0, Int(position * 1000))
        let currentDuration = max(0, Int((duration ?? 0) * 1000))

        do {
            let repository = try PlaybackRepository(context: context)
            let response = try await repository.updateTimeline(
                ratingKey: ratingKey,
                state: state,
                time: currentTime,
                duration: currentDuration,
                sessionIdentifier: sessionIdentifier,
                playQueueItemID: currentPlayQueueItemID(),
            )
            handleTerminationIfNeeded(response)
        } catch {
            if let recoveryError = error as? PlexServerAccessRecoveryError {
                serverAccessRecoveryError = recoveryError
            }
            debugPrint("Failed to update timeline:", error)
        }
    }

    private func loadRemoteMetadata(using repository: MetadataRepository) async throws {
        let params = MetadataRepository.PlexMetadataParams(
            checkFiles: true,
            includeChapters: true,
            includeMarkers: true,
        )
        let response = try await repository.getMetadata(
            ratingKey: ratingKey,
            params: params,
        )
        let metadata = response.mediaContainer.metadata?.first
        media = metadata.map(MediaItem.init)
        markers = metadata?.markers ?? []
        chapters = (metadata?.chapters ?? [])
            .filter(\.isValid)
            .sorted {
                if $0.startTimeOffset == $1.startTimeOffset {
                    return $0.index < $1.index
                }
                return $0.startTimeOffset < $1.startTimeOffset
            }
        updatePartContext(from: metadata)
        scrubThumbnailSource = PlexBIFSource(
            partID: activePartId,
            context: context,
        )
        resolvePreferredStreams(from: metadata)
        guard let resolvedURL = resolvePlaybackURL(from: metadata) else {
            throw PlexAPIError.invalidURL
        }
        playbackURL = resolvedURL
        serverAccessRecoveryError = nil
        errorMessage = nil
    }

    private func resolvePlaybackURL(from metadata: PlexItem?) -> URL? {
        guard
            let partPath = metadata?.media?.first?.parts.first?.key,
            let mediaRepository = try? MediaRepository(context: context)
        else {
            return nil
        }

        return mediaRepository.mediaURL(path: partPath)
    }

    private func refreshPlayQueue() async {
        guard shouldReportPlaybackToServer else { return }
        do {
            let manager = try PlayQueueManager(context: context)
            playQueueState = try await manager.fetchQueue(id: playQueueState.id)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            debugPrint("Failed to refresh play queue:", error)
            ErrorReporter.capture(error)
        }
    }

    private func resolvePreferredStreams(from metadata: PlexItem?) {
        let streams = metadata?.media?.first?.parts.first?.stream ?? []

        preferredAudioStreamFFIndex = streams.first {
            $0.streamType == .audio && $0.selected == true
        }?.index

        preferredSubtitleStreamID = streams.first {
            $0.streamType == .subtitle && $0.selected == true
        }?.id
    }

    private func updatePartContext(from metadata: PlexItem?) {
        let part = metadata?.media?.first?.parts.first
        activePartId = part?.id
        activePartFile = part?.file

        let streams = part?.stream ?? []
        partStreams = streams
        streamsByFFIndex = streams.reduce(into: [Int: PlexPartStream]()) { result, stream in
            guard let index = stream.index else { return }
            result[index] = stream
        }
        streamsByID = streams.reduce(into: [Int: PlexPartStream]()) { result, stream in
            guard let id = stream.id else { return }
            result[id] = stream
        }
    }

    private func currentPlayQueueItemID() -> Int? {
        let currentRatingKey = media?.id ?? (ratingKey.isEmpty ? nil : ratingKey)
        guard let currentRatingKey else { return nil }
        return playQueueState.items.first { $0.ratingKey == currentRatingKey }?.playQueueItemID
    }

    private func activeMarker(where predicate: (PlexMarker) -> Bool) -> PlexMarker? {
        markers.first { predicate($0) && $0.contains(time: position) }
    }

    func automaticSkipMarker(
        autoSkipIntros: Bool,
        autoSkipCredits: Bool,
    ) -> PlexMarker? {
        if let automaticSkipMarkerInFlight {
            guard !automaticSkipMarkerInFlight.contains(time: position) else { return nil }
            self.automaticSkipMarkerInFlight = nil
        }

        guard let marker = markers.first(where: {
            $0.contains(time: position)
                && (($0.isIntro && autoSkipIntros) || ($0.isCredits && autoSkipCredits))
        }) else {
            return nil
        }

        automaticSkipMarkerInFlight = marker
        return marker
    }

    private func handleTerminationIfNeeded(_ response: PlexTimelineResponse) {
        guard shouldReportPlaybackToServer else { return }
        guard
            !didReceiveTermination,
            let terminationText = response.mediaContainer.terminationText,
            !terminationText.isEmpty
        else {
            return
        }

        didReceiveTermination = true
        terminationMessage = terminationText
        Task {
            await sendStoppedAfterTermination()
        }
    }

    private func sendStoppedAfterTermination() async {
        guard shouldReportPlaybackToServer else { return }
        let currentTime = max(0, Int(position * 1000))
        let currentDuration = max(0, Int((duration ?? 0) * 1000))

        do {
            let repository = try PlaybackRepository(context: context)
            _ = try await repository.updateTimeline(
                ratingKey: ratingKey,
                state: .stopped,
                time: currentTime,
                duration: currentDuration,
                sessionIdentifier: sessionIdentifier,
            )
        } catch {
            debugPrint("Failed to report termination stop:", error)
        }
    }

    func persistStreamSelection(for track: PlayerTrack) async {
        guard shouldReportPlaybackToServer else { return }
        guard
            let streamId = track.plexStreamID,
            let partId = activePartId
        else {
            return
        }

        do {
            let playbackRepository = try PlaybackRepository(context: context)
            switch track.type {
            case .audio:
                try await playbackRepository.setPreferredStreams(
                    partId: partId,
                    audioStreamId: streamId,
                )
            case .subtitle:
                try await playbackRepository.setPreferredStreams(
                    partId: partId,
                    subtitleStreamId: streamId,
                )
            case .video:
                break
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }

    func persistSubtitleStreamSelection(for track: PlayerTrack?) async {
        guard shouldReportPlaybackToServer, let partId = activePartId else { return }

        let streamId: Int?
        if let track {
            guard let plexStreamID = track.plexStreamID else { return }
            streamId = plexStreamID
        } else {
            streamId = nil
        }

        do {
            let playbackRepository = try PlaybackRepository(context: context)
            try await playbackRepository.setPreferredSubtitleStream(
                partId: partId,
                subtitleStreamId: streamId,
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }
}

private enum PlexSubtitleActivationError: LocalizedError {
    case missingSelectedExternalTrack

    var errorDescription: String? {
        String(localized: "subtitles.search.activation.error")
    }
}
