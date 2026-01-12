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
    var isPaused = false
    var preferredAudioStreamFFIndex: Int?
    var preferredSubtitleStreamFFIndex: Int?
    var resumePosition: Double? {
        media?.viewOffset
    }

    var markers: [PlexMarker] = []
    var activeSkipMarker: PlexMarker? {
        activeMarker(where: \.isIntro)
            ?? activeMarker(where: \.isCredits)
    }

    @ObservationIgnored private let timelineInterval: TimeInterval = 10
    @ObservationIgnored private var lastTimelineSentAt: Date?
    @ObservationIgnored private var lastTimelineState: PlaybackRepository.PlaybackState?
    @ObservationIgnored private let ratingKey: String
    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let shouldResumeFromOffsetFlag: Bool
    @ObservationIgnored private var activePartId: Int?
    @ObservationIgnored private var streamsByFFIndex: [Int: PlexPartStream] = [:]
    @ObservationIgnored private let sessionIdentifier = UUID().uuidString
    @ObservationIgnored private var didReceiveTermination = false
    var terminationMessage: String?

    func plexStream(forFFIndex ffIndex: Int?) -> PlexPartStream? {
        guard let ffIndex else { return nil }
        return streamsByFFIndex[ffIndex]
    }

    init(ratingKey: String, context: PlexAPIContext, shouldResumeFromOffset: Bool = true) {
        self.ratingKey = ratingKey
        self.context = context
        shouldResumeFromOffsetFlag = shouldResumeFromOffset
    }

    var shouldResumeFromOffset: Bool {
        shouldResumeFromOffsetFlag
    }

    func load() async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            errorMessage = String(localized: "errors.selectServer.playMedia")
            return
        }

        isLoading = true
        errorMessage = nil
        preferredAudioStreamFFIndex = nil
        preferredSubtitleStreamFFIndex = nil
        activePartId = nil
        streamsByFFIndex = [:]
        markers = []
        defer { isLoading = false }

        do {
            let params = MetadataRepository.PlexMetadataParams(
                checkFiles: true,
                includeChapters: true,
                includeMarkers: true,
            )
            let response = try await metadataRepository.getMetadata(
                ratingKey: ratingKey,
                params: params,
            )
            let metadata = response.mediaContainer.metadata?.first
            media = metadata.map(MediaItem.init)
            markers = metadata?.markers ?? []
            updatePartContext(from: metadata)
            resolvePreferredStreams(from: metadata)
            playbackURL = resolvePlaybackURL(from: metadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handlePropertyChange(
        property: PlayerProperty,
        data: Any?,
        isScrubbing: Bool,
    ) {
        let previousState = playbackState
        var stateChanged = false

        switch property {
        case .pause:
            isPaused = (data as? Bool) ?? false
            stateChanged = previousState != playbackState
        case .pausedForCache:
            isBuffering = (data as? Bool) ?? false
            stateChanged = previousState != playbackState
        case .timePos:
            guard !isScrubbing else { return }
            position = data as? Double ?? 0.0
            reportTimeline(state: playbackState)
        case .duration:
            duration = data as? Double
        case .demuxerCacheDuration:
            bufferedAhead = data as? Double ?? 0.0
        default:
            break
        }

        if stateChanged {
            reportTimeline(state: playbackState, force: true)
        }
    }

    func handleStop() {
        reportTimeline(state: .stopped, force: true)
    }

    func markPlaybackFinished() async {
        let currentDuration = max(0, Int((media?.duration ?? duration ?? position) * 1000))

        do {
            let repository = try PlaybackRepository(context: context)
            _ = try await repository.updateTimeline(
                ratingKey: ratingKey,
                state: .stopped,
                time: currentDuration,
                duration: currentDuration,
                sessionIdentifier: sessionIdentifier,
            )
        } catch {
            debugPrint("Failed to mark playback as finished:", error)
        }
    }

    func fetchOnDeckEpisode(grandparentRatingKey: String) async -> PlexItem? {
        do {
            let repository = try MetadataRepository(context: context)
            let params = MetadataRepository.PlexMetadataParams(includeOnDeck: true)
            let response = try await repository.getMetadata(
                ratingKey: grandparentRatingKey,
                params: params,
            )

            return response.mediaContainer.metadata?.first?.onDeck?.metadata
        } catch {
            debugPrint("Failed to fetch on deck metadata:", error)
            return nil
        }
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
            )
            handleTerminationIfNeeded(response)
        } catch {
            debugPrint("Failed to update timeline:", error)
        }
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

    private func resolvePreferredStreams(from metadata: PlexItem?) {
        let streams = metadata?.media?.first?.parts.first?.stream ?? []

        preferredAudioStreamFFIndex = streams.first {
            $0.streamType == .audio && $0.selected == true
        }?.index

        preferredSubtitleStreamFFIndex = streams.first {
            $0.streamType == .subtitle && $0.selected == true
        }?.index
    }

    private func updatePartContext(from metadata: PlexItem?) {
        let part = metadata?.media?.first?.parts.first
        activePartId = part?.id

        let streams = part?.stream ?? []
        streamsByFFIndex = streams.reduce(into: [Int: PlexPartStream]()) { result, stream in
            guard let index = stream.index else { return }
            result[index] = stream
        }
    }

    private func activeMarker(where predicate: (PlexMarker) -> Bool) -> PlexMarker? {
        markers.first { predicate($0) && $0.contains(time: position) }
    }

    private func handleTerminationIfNeeded(_ response: PlexTimelineResponse) {
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
        guard
            let ffIndex = track.ffIndex,
            let stream = streamsByFFIndex[ffIndex],
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
                    audioStreamId: stream.id,
                )
            case .subtitle:
                try await playbackRepository.setPreferredStreams(
                    partId: partId,
                    subtitleStreamId: stream.id,
                )
            case .video:
                break
            }
        } catch {
            debugPrint("Failed to persist stream selection:", error)
        }
    }
}
