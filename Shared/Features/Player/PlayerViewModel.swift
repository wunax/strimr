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
    var preferredSubtitleSelectionIsOff = false
    var terminationMessage: String?
    var selectedQuality: TranscodeQualityPreset = .original
    var qualityFallbackMessage: String?
    /// Shown once when the player opens, such as an external player that could not be opened.
    var launchNotice: String?
    var isLivePlayback: Bool {
        liveContext != nil
    }

    /// Live streams cannot play faster than real time, and SharePlay takes the group's rate.
    func initialPlaybackRate(settings: PlaybackSettings, isSharePlay: Bool) -> Float {
        isLivePlayback || isSharePlay ? 1.0 : settings.defaultPlaybackRate
    }

    var liveChannel: LiveTVChannel? {
        liveContext?.channel
    }

    var liveProgram: LiveTVProgram?
    var liveCaptureRange: LiveTVCaptureRange?
    var liveRoutePreference = LiveTVRoutePreference.automatic
    private(set) var liveSource: LiveTVPlaybackSource?

    var liveRoute: LiveTVPlaybackRoute? {
        liveSource?.route
    }

    func liveLoadOptions(routesAudioToAirPlay: Bool) -> LiveLoadOptions? {
        guard isLivePlayback, let liveSource else { return nil }
        return LiveLoadOptions.make(
            route: liveSource.route,
            nativeRemoteHLS: liveSource.nativeRemoteHLS,
            captureDuration: liveCaptureRange?.duration,
            isInterlaced: liveSource.isInterlaced,
            routesAudioToAirPlay: routesAudioToAirPlay,
            preferredLanguages: Locale.preferredLanguages,
        )
    }

    /// The channel is tuning: the player shows the program's artwork instead of black.
    private(set) var isJoiningLive = false
    /// Changes each time a channel comes on screen, which shows the zap banner.
    private(set) var liveChannelArrivals = 0
    @ObservationIgnored private var lastLiveChannelIndex: Int?

    var liveChannels: [LiveTVChannel] {
        liveContext?.channels ?? []
    }

    var liveChannelIndex: Int? {
        liveContext?.selectedIndex
    }

    var liveStore: LiveTVStore? {
        isLivePlayback ? mediaServices?.liveTVStore : nil
    }

    var lastLiveChannel: LiveTVChannel? {
        guard let lastLiveChannelIndex, liveChannels.indices.contains(lastLiveChannelIndex) else { return nil }
        return liveChannels[lastLiveChannelIndex]
    }

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

    var burnsSubtitles: Bool {
        playbackPlan?.burnsSubtitles ?? false
    }

    var playbackStatisticsContext: PlaybackStatisticsContext {
        PlaybackStatisticsContext(
            method: isLocalPlayback ? .offline : playbackPlan?.method,
            quality: playbackPlan?.effectiveQuality ?? .original,
            burnsSubtitles: burnsSubtitles,
        )
    }

    var resumePosition: Double? {
        media?.viewOffset
    }

    var markers: [SkipSegment] = []
    var chapters: [MediaChapter] = []

    var activeSkipMarker: SkipSegment? {
        activeMarker(where: \.isIntro) ?? activeMarker(where: \.isCommercial) ?? activeMarker(where: \.isCredits)
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

    /// Server whose services the player uses; `nil` for downloads.
    var serverIdentity: ServerIdentity? {
        mediaServices?.identity
    }

    func nowPlayingItem(settings: PlaybackSettings) -> NowPlayingItem? {
        NowPlayingItem(
            media: media,
            artworkService: artworkServices?.artwork,
            skipBackwardSeconds: settings.seekBackwardSeconds,
            skipForwardSeconds: settings.seekForwardSeconds,
        )
    }

    var subtitleSearchTitlePlaceholder: String {
        media?.title ?? ""
    }

    var usesCommonPlaybackQueue: Bool {
        #if !os(tvOS)
            // Downloaded episodes chain through the other downloads of the series.
            if isLocalPlayback {
                return true
            }
        #endif
        return mediaServices != nil && !isLivePlayback
    }

    #if !os(tvOS)
        /// Server of a streaming session; `nil` for downloads and Live TV.
        var streamingServer: ServerIdentity? {
            guard !isLocalPlayback, !isLivePlayback else { return nil }
            return mediaServices?.identity
        }

        /// The stream lost its server: the current position is kept locally and the downloaded copy, if any, is
        /// returned so playback can continue from it.
        func prepareOfflineHandoff() -> LocalPlaybackRequest? {
            guard let media, let mediaServices, let store = OfflineCoordinator.shared.store else { return nil }
            PlaybackProgressRecorder.recordInterruptedStream(
                owner: mediaServices.owner,
                itemID: media.id,
                position: position,
                duration: duration ?? media.duration,
                store: store,
            )
            return DownloadManager.shared?.localPlaybackRequest(for: media.identity, kind: media.kind)
        }
    #endif

    var canResetRememberedTrackSelections: Bool {
        media?.trackSelectionScope != nil && mediaServices?.trackSelectionCoordinator != nil
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
    @ObservationIgnored private var trackerSession: TrackerPlaybackSession?
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
    /// Bumped by each subtitle choice made by hand, which an automatic search in progress must not override.
    @ObservationIgnored private var manualSubtitleChanges = 0
    @ObservationIgnored private var liveContext: LiveTVLaunchContext?
    @ObservationIgnored private var liveSession: (any LiveTVPlaybackSession)?
    @ObservationIgnored private var isSwitchingLiveChannel = false
    @ObservationIgnored private var isLiveReportingSuspended = false
    @ObservationIgnored private var pendingLiveSessionToStop: (any LiveTVPlaybackSession)?
    @ObservationIgnored private var liveSessionGeneration = 0
    @ObservationIgnored private var liveTimelineTask: Task<Void, Never>?
    @ObservationIgnored private var liveWatchTask: Task<Void, Never>?
    @ObservationIgnored private var pendingLiveTimelineState: TimelineState?
    #if !os(tvOS)
        @ObservationIgnored private var progressRecorder: PlaybackProgressRecorder?
        @ObservationIgnored private var localOwner: MediaOwner?
    #endif

    init(
        queue: PlaybackQueue,
        services: MediaServices,
        shouldResumeFromOffset: Bool = true,
        launchNotice: String? = nil,
    ) {
        self.launchNotice = launchNotice
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

    #if !os(tvOS)
        /// Plays a downloaded file. With an owner, progress is journaled locally, pushed live when the owner's
        /// server is reachable, and playback resumes from the latest local position.
        init(
            localMedia: MediaItem,
            localPlaybackURL: URL,
            localExternalSubtitles: [ExternalSubtitleTrack] = [],
            owner: MediaOwner? = nil,
            resumes: Bool = true,
        ) {
            let recorder = owner.flatMap {
                OfflineCoordinator.shared.makeRecorder(owner: $0, itemID: localMedia.id, duration: localMedia.duration)
            }
            let resumePosition = resumes ? recorder?.resumePosition : nil
            let media = resumePosition.map { position in
                localMedia.applying(OfflineWatchState(
                    viewOffset: position,
                    viewCount: localMedia.viewCount ?? 0,
                    played: false,
                    lastViewedAt: localMedia.lastViewedAt,
                    source: .local,
                ))
            } ?? localMedia
            ratingKey = localMedia.id
            mediaServices = nil
            mediaQueue = nil
            shouldResumeFromOffsetFlag = resumePosition != nil
            self.localMedia = media
            self.localPlaybackURL = localPlaybackURL
            self.localExternalSubtitles = localExternalSubtitles
            self.media = media
            playbackURL = localPlaybackURL
            selectedQuality = .original
            progressRecorder = recorder
            localOwner = owner
        }

        convenience init(request: LocalPlaybackRequest) {
            self.init(
                localMedia: request.media,
                localPlaybackURL: request.url,
                localExternalSubtitles: request.externalSubtitles,
                owner: request.owner,
                resumes: request.resumes,
            )
        }
    #endif

    init(live context: LiveTVLaunchContext, services: MediaServices) {
        liveContext = context
        mediaServices = services
        mediaQueue = nil
        ratingKey = context.channel.providerID
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
            title: track.name,
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
        return playbackPlan?.externalSubtitles ?? []
    }

    func sourcePlayerTracks() -> [PlayerTrack] {
        guard let playbackPlan else { return [] }
        return Self.sourcePlayerTracks(
            playbackPlan.tracks,
            selectedAudioIndex: playbackPlan.selectedAudioIndex,
            selectedSubtitleIndex: playbackPlan.selectedSubtitleIndex,
        )
    }

    static func sourcePlayerTracks(
        _ tracks: [PlaybackTrack],
        selectedAudioIndex: Int?,
        selectedSubtitleIndex: Int?,
    ) -> [PlayerTrack] {
        tracks.map { track in
            let providerStreamID = Int(track.id) ?? track.sourceIndex
            let isSelected = switch track.kind {
            case .audio:
                selectedAudioIndex == track.sourceIndex
            case .subtitle:
                selectedSubtitleIndex == providerStreamID
                    || selectedSubtitleIndex == track.sourceIndex
            }
            return PlayerTrack(
                id: track.sourceIndex,
                ffIndex: track.sourceIndex,
                providerStreamID: providerStreamID,
                type: track.kind == .audio ? .audio : .subtitle,
                // Like the engine's tracks in direct play, so a remembered title is the stream's own name.
                title: track.name ?? track.title,
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
        #if !os(tvOS)
            if isLocalPlayback {
                // Offline chaining only uses downloaded episodes.
                guard let media,
                      let next = DownloadManager.shared?.nextDownloadedEpisode(after: media),
                      let request = DownloadManager.shared?.localPlaybackRequest(for: next, resumes: false)
                else { return nil }
                return PlayerViewModel(request: request)
            }
        #endif
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
                isJoiningLive = true
                let session = try await mediaServices.liveTV.startPlayback(
                    channel: liveContext.channel,
                    route: liveRoutePreference,
                )
                let offset = liveContext.startsFromBeginning
                    ? session.captureRange.flatMap { range in
                        liveContext.program.map { max(0, $0.startDate.timeIntervalSince(range.startDate)) }
                    }
                    : nil
                let source = try await session.source(offsetFromCaptureStart: offset)
                adoptLiveSession(session)
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
                trackPreference: rememberedTrackPreference,
                version: mediaServices.versionRequest(for: media),
            )
            apply(plan: plan)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            serverAccessRecoveryError = mediaServices.playback.serverAccessRecoveryError(from: error)
            if isLivePlayback {
                isJoiningLive = false
                LiveTVErrorReporting.capture(error, route: liveRoute)
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
            let previous = liveSession
            adoptLiveSession(replacement)
            apply(liveSource: source)
            await previous.stop()
            return source.url
        }
        guard let mediaServices, let media else { throw PlayerPlaybackError.missingPlaybackURL }

        do {
            let previousPlan = playbackPlan
            let plan = try await mediaServices.playback.prepare(
                media: media,
                resume: shouldResumeFromOffsetFlag,
                quality: selectedQuality,
                trackPreference: rememberedTrackPreference,
                version: currentVersionRequest(services: mediaServices, media: media),
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
        guard !isLivePlayback, !isLocalPlayback, let mediaServices,
              let media else { throw PlayerPlaybackError.missingPlaybackURL }
        if !force, quality == selectedQuality, let playbackURL {
            return playbackURL
        }

        let previousPlan = playbackPlan
        let plan = try await mediaServices.playback.prepare(
            media: media,
            resume: false,
            quality: quality,
            trackPreference: rememberedTrackPreference,
            version: currentVersionRequest(services: mediaServices, media: media),
        )
        selectedQuality = quality
        apply(plan: plan)
        if let previousPlan {
            await mediaServices.playback.release(plan: previousPlan)
        }
        return plan.url
    }

    /// Reloads another version of the current item and returns where to resume it.
    func changeVersion(
        to versionID: String,
        from position: TimeInterval,
    ) async throws -> (url: URL, position: TimeInterval) {
        guard !isLivePlayback, !isLocalPlayback, let mediaServices,
              let media else { throw PlayerPlaybackError.missingPlaybackURL }

        let previousPlan = playbackPlan
        // Track ids are specific to each file: carry the preference by language, not the old stream index.
        // Without remembered tracks, keep what is playing now so switching files never changes the language.
        let trackPreference = rememberedTrackPreference?.matchingAcrossItems
            ?? previousPlan.map { plan in
                Self.sessionTrackPreference(
                    tracks: plan.tracks,
                    audioSourceIndex: preferredAudioStreamFFIndex,
                    subtitleStreamID: preferredSubtitleStreamID,
                    subtitleIsOff: preferredSubtitleSelectionIsOff,
                )
            }
        let plan = try await mediaServices.playback.prepare(
            media: media,
            resume: false,
            quality: selectedQuality,
            trackPreference: trackPreference,
            version: .explicit(versionID: versionID),
        )
        apply(plan: plan)
        if let previousPlan {
            await mediaServices.playback.release(plan: previousPlan)
        }
        let selectedVersion = plan.versions.first { version in
            plan.versionID.map(version.matchesVersionID) ?? false
        }
        // A provider fallback to another version is not the user's choice and must not become the preference.
        if let selectedVersion, selectedVersion.matchesVersionID(versionID), let scope = media.trackSelectionScope {
            mediaServices.rememberVersion(selectedVersion, for: scope)
        }
        let duration = selectedVersion?.duration ?? plan.media.duration
        let resumePosition = duration.map { min(position, max(0, $0 - 5)) } ?? position
        return (plan.url, resumePosition)
    }

    /// Describes the playing tracks by attributes only, for matching in another file. Never stored.
    static func sessionTrackPreference(
        tracks: [PlaybackTrack],
        audioSourceIndex: Int?,
        subtitleStreamID: Int?,
        subtitleIsOff: Bool,
    ) -> MediaTrackPreference {
        let audio = tracks.first { $0.kind == .audio && $0.sourceIndex == audioSourceIndex }
        let subtitle = tracks.first { track in
            track.kind == .subtitle && (Int(track.id) ?? track.sourceIndex) == subtitleStreamID
        }
        let subtitlePreference: MediaSubtitlePreference = if let subtitle {
            .track(
                streamIndex: nil,
                language: subtitle.language,
                title: subtitle.name ?? subtitle.title,
                codec: subtitle.codec ?? "",
                isForced: subtitle.isForced,
                isHearingImpaired: subtitle.isHearingImpaired,
            )
        } else if subtitleIsOff || subtitleStreamID == nil {
            .off
        } else {
            // A subtitle missing from the plan (e.g. attached during playback) cannot be described.
            .serverDefault
        }
        return MediaTrackPreference(
            audioStreamIndex: nil,
            audioLanguage: audio?.language,
            audioTitle: audio?.name ?? audio?.title,
            audioCodec: audio?.codec,
            audioIsHearingImpaired: audio?.isHearingImpaired,
            audioIsCommentary: nil,
            subtitle: subtitlePreference,
        )
    }

    var availableVersions: [MediaFileVersion] {
        guard !isLivePlayback, !isLocalPlayback else { return [] }
        return playbackPlan?.versions ?? []
    }

    var showsVersionSelection: Bool {
        availableVersions.count > 1
    }

    var versionOptions: [PlaybackSettingsVersion] {
        guard showsVersionSelection else { return [] }
        return PlaybackSettingsVersion.options(versions: availableVersions, selectedID: currentVersionID)
    }

    var currentVersionID: String? {
        playbackPlan?.versionID
    }

    private func currentVersionRequest(services: MediaServices, media: MediaItem) -> MediaVersionRequest {
        if let versionID = playbackPlan?.versionID {
            return .explicit(versionID: versionID)
        }
        return services.versionRequest(for: media)
    }

    /// Downloads a subtitle when the media has none in the wanted language. Nil when there is nothing to tell the user.
    func searchMissingSubtitle(settings: PlaybackSettings) async -> AutomaticSubtitleSearchOutcome? {
        guard settings.automaticSubtitleSearch,
              canSearchSubtitles,
              !isLivePlayback,
              let mediaServices,
              let media,
              media.type == .movie || media.type == .episode,
              let playbackPlan
        else { return nil }

        let changesAtStart = manualSubtitleChanges
        var isStillWanted: Bool {
            !Task.isCancelled && manualSubtitleChanges == changesAtStart
        }

        let account: AccountPreferences?
        do {
            account = try await mediaServices.accountPreferences?.load()
        } catch {
            // The account may have refused subtitles or want another language, and a download stays on the server.
            if !Task.isCancelled, !error.isCancellation {
                ErrorReporter.capture(error)
            }
            return nil
        }
        guard isStillWanted,
              let language = AutomaticSubtitleSearch.language(
                  remembered: rememberedTrackPreference?.subtitle,
                  account: account,
                  deviceLanguage: Locale.preferredLanguages.first ?? "en",
              ),
              AutomaticSubtitleSearch.isMissing(
                  language: language,
                  audioLanguage: playbackPlan.audioLanguage(sourceIndex: preferredAudioStreamFFIndex),
                  subtitles: playbackPlan.existingSubtitles,
              )
        else { return nil }

        do {
            let results = try await mediaServices.detail.searchSubtitles(
                itemID: media.id,
                language: language,
                hearingImpaired: mediaServices.detail.supportsAdvancedSubtitleSearch
                    && settings.subtitleSearch.hearingImpaired,
                forced: false,
                title: nil,
            ).rankedByMatch()
            guard isStillWanted else { return nil }
            // Servers can return forced results in a search for full subtitles.
            guard let result = results.first(where: { !$0.isForced }) else { return .notFound(language: language) }

            // The plan only lists the played version, while the refresh below can cover all of them.
            let previous = try await mediaServices.playback.externalSubtitles(media: media)
            guard isStillWanted else { return nil }
            try await mediaServices.detail.installSubtitle(itemID: media.id, result: result)
            guard isStillWanted else { return nil }

            let refreshed = try await mediaServices.playback.externalSubtitles(media: media)
            guard isStillWanted else { return nil }
            guard let subtitle = AutomaticSubtitleSearch.installedSubtitle(
                in: refreshed,
                previousURLs: Set(previous.map(\.track.url)),
                language: language,
            ) else { throw PlayerPlaybackError.missingExternalSubtitle }
            return .attached(subtitle, language: language)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return nil }
            ErrorReporter.capture(error)
            return .failed(language: language)
        }
    }

    func refreshMetadataAfterSubtitleAttachment() async throws -> PlayerExternalSubtitle {
        manualSubtitleChanges += 1
        guard !isLocalPlayback,
              let mediaServices,
              let media
        else { throw PlayerPlaybackError.missingExternalSubtitle }

        let previousURLs = Set(playbackPlan?.externalSubtitles.map(\.track.url) ?? [])
        do {
            let refreshed = try await mediaServices.playback.externalSubtitles(media: media)
            guard let subtitle = refreshed.first(where: { !previousURLs.contains($0.track.url) }) ?? refreshed.first
            else {
                throw PlayerPlaybackError.missingExternalSubtitle
            }
            return subtitle
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
            reportTrackerState()
        }
    }

    func handlePlaybackPosition(_ position: Double, isScrubbing: Bool) {
        guard !isScrubbing else { return }
        #if DEBUG
            // The demo clip lasts seconds; the timeline places it at a moment of the full film.
            self.position = DemoMode.isEnabled ? position + DemoMode.playerOffset : position
        #else
            self.position = position
        #endif
        reportTimeline(state: playbackState)
    }

    func handlePlaybackDuration(_ duration: Double?) {
        #if DEBUG
            self.duration = DemoMode.isEnabled ? media?.duration ?? duration : duration
        #else
            self.duration = duration
        #endif
    }

    func handleBufferedAhead(_ bufferedAhead: Double) {
        self.bufferedAhead = bufferedAhead
    }

    func handleStop() {
        trackerSession?.stopped(position: position, duration: duration ?? media?.duration)
        #if !os(tvOS)
            if let progressRecorder {
                progressRecorder.stop(position: position)
                return
            }
        #endif
        if let liveSession {
            self.liveSession = nil
            invalidateLiveReporting()
            liveWatchTask?.cancel()
            mediaServices?.liveTVStore.notePlaybackEnded(on: liveSession.channel.identity)
            let pending = pendingLiveSessionToStop
            pendingLiveSessionToStop = nil
            Task {
                await liveSession.stop()
                await pending?.stop()
            }
            return
        }
        if let pending = pendingLiveSessionToStop {
            pendingLiveSessionToStop = nil
            invalidateLiveReporting()
            Task { await pending.stop() }
            return
        }
        guard let mediaServices, let playbackPlan else { return }
        Task {
            do {
                try await mediaServices.playback.reportStopped(
                    plan: playbackPlan,
                    position: position,
                    currentSelection: currentPlaybackStreamSelection,
                )
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
        invalidateLiveReporting()
        let pending = pendingLiveSessionToStop
        pendingLiveSessionToStop = nil
        await liveSession.stop()
        await pending?.stop()
        return true
    }

    func leaveLiveBackground() {
        isLiveReportingSuspended = false
        if liveSession != nil {
            reportTimeline(state: playbackState, force: true)
        }
    }

    func markPlaybackFinished() async {
        trackerSession?.finished()
        #if !os(tvOS)
            if let progressRecorder {
                progressRecorder.finish()
                return
            }
        #endif
        if let liveSession {
            self.liveSession = nil
            invalidateLiveReporting()
            let pending = pendingLiveSessionToStop
            pendingLiveSessionToStop = nil
            await liveSession.stop()
            await pending?.stop()
            return
        }
        guard let mediaServices, let playbackPlan else { return }
        do {
            try await mediaServices.playback.reportStopped(
                plan: playbackPlan,
                position: media?.duration ?? duration ?? position,
                currentSelection: currentPlaybackStreamSelection,
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
        autoSkipCommercials: Bool,
    ) -> SkipSegment? {
        if let automaticSkipMarkerInFlight {
            guard !automaticSkipMarkerInFlight.contains(time: position) else { return nil }
            self.automaticSkipMarkerInFlight = nil
        }

        guard let marker = markers.first(where: {
            guard $0.contains(time: position) else { return false }
            return switch $0.kind {
            case .intro: autoSkipIntros
            case .credits: autoSkipCredits
            case .commercial: autoSkipCommercials
            }
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
                try await mediaServices.detail.selectAudioTrack(
                    id: streamID,
                    itemID: itemID,
                    versionID: playbackPlan?.versionID,
                )
            case .subtitle:
                try await mediaServices.detail.selectSubtitleTrack(
                    id: streamID,
                    itemID: itemID,
                    versionID: playbackPlan?.versionID,
                )
            case .video:
                break
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
        if track.type == .audio, let media {
            preferredAudioStreamFFIndex = track.ffIndex ?? track.providerStreamID
            let coordinator = mediaServices.trackSelectionCoordinator
            coordinator?.rememberAudio(
                track,
                for: media,
                server: mediaServices.identity,
                accountIdentifier: mediaServices.trackSelectionAccountIdentifier ?? "default",
            )
            await synchronizeServerTrackMemory(
                kind: .audio,
                coordinator: coordinator,
            )
        }
    }

    func persistSubtitleStreamSelection(for track: PlayerTrack?) async {
        manualSubtitleChanges += 1
        guard let mediaServices, let itemID = media?.id else { return }
        let streamID = track?.providerStreamID
        do {
            try await mediaServices.detail.selectSubtitleTrack(
                id: streamID,
                itemID: itemID,
                versionID: playbackPlan?.versionID,
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
        preferredSubtitleStreamID = streamID
        preferredSubtitleSelectionIsOff = track == nil
        if let media {
            let coordinator = mediaServices.trackSelectionCoordinator
            coordinator?.rememberSubtitle(
                track,
                for: media,
                server: mediaServices.identity,
                accountIdentifier: mediaServices.trackSelectionAccountIdentifier ?? "default",
            )
            await synchronizeServerTrackMemory(
                kind: .subtitle,
                coordinator: coordinator,
            )
        }
    }

    private var playbackState: TimelineState {
        if isBuffering {
            return .buffering
        }
        return isPaused ? .paused : .playing
    }

    private func synchronizeServerTrackMemory(
        kind: PlaybackTrackKind,
        coordinator: TrackSelectionCoordinator?,
    ) async {
        guard coordinator?.isEnabled == true,
              let memoryService = mediaServices?.playback as? any MediaTrackSelectionMemoryService
        else { return }
        do {
            try await memoryService.enableTrackSelectionMemory(for: kind)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }

    private func activeMarker(where predicate: (SkipSegment) -> Bool) -> SkipSegment? {
        markers.first { predicate($0) && $0.contains(time: position) }
    }

    private func resetPlaybackMetadata() {
        preferredAudioStreamFFIndex = nil
        preferredSubtitleStreamID = nil
        preferredSubtitleSelectionIsOff = false
        scrubThumbnailSource = nil
        automaticSkipMarkerInFlight = nil
        markers = []
        chapters = []
    }

    func switchLiveChannel(by offset: Int) async throws -> URL {
        guard let context = liveContext else { throw PlayerPlaybackError.missingPlaybackURL }
        return try await switchLiveChannel(to: context.selectedIndex + offset)
    }

    /// Goes back to the channel watched before this one.
    func switchToLastLiveChannel() async throws -> URL {
        guard let lastLiveChannelIndex else { throw PlayerPlaybackError.missingPlaybackURL }
        return try await switchLiveChannel(to: lastLiveChannelIndex)
    }

    func switchLiveChannel(to index: Int) async throws -> URL {
        guard !isSwitchingLiveChannel, let context = liveContext, let mediaServices,
              index != context.selectedIndex,
              context.channels.indices.contains(index) else { throw PlayerPlaybackError.missingPlaybackURL }
        isSwitchingLiveChannel = true
        isJoiningLive = true
        defer { isSwitchingLiveChannel = false }

        let replacementContext = LiveTVLaunchContext(channels: context.channels, selectedIndex: index)
        do {
            let replacement = try await mediaServices.liveTV.startPlayback(
                channel: replacementContext.channel,
                route: liveRoutePreference,
            )
            do {
                let source = try await replacement.source(offsetFromCaptureStart: nil)
                let previous = liveSession
                lastLiveChannelIndex = context.selectedIndex
                liveContext = replacementContext
                adoptLiveSession(replacement)
                pendingLiveSessionToStop = previous
                media = Self.liveMedia(channel: replacementContext.channel, server: mediaServices.identity)
                apply(liveSource: source)
                return source.url
            } catch {
                await replacement.stop()
                throw error
            }
        } catch {
            isJoiningLive = false
            throw error
        }
    }

    /// Moves the current channel to the server-transcoded route once, after the engine failed to demux it.
    func fallBackToServerTranscode() async throws -> URL? {
        guard let liveSession, let replacement = try await liveSession.fallback() else { return nil }
        let source = try await replacement.source(offsetFromCaptureStart: nil)
        if replacement !== liveSession {
            adoptLiveSession(replacement)
            await liveSession.stop()
        }
        apply(liveSource: source)
        return source.url
    }

    func confirmLiveChannelSwitch() {
        if isJoiningLive {
            isJoiningLive = false
            liveChannelArrivals += 1
        }
        guard let pendingLiveSessionToStop else { return }
        self.pendingLiveSessionToStop = nil
        Task { await pendingLiveSessionToStop.stop() }
    }

    private func apply(liveSource source: LiveTVPlaybackSource) {
        playbackURL = source.url
        playbackHTTPHeaders = source.httpHeaders
        liveProgram = source.program
        liveCaptureRange = source.captureRange
        liveSource = source
        duration = source.nativeRemoteHLS ? source.captureRange?.duration : nil
        markers = []
        chapters = []
        scrubThumbnailSource = nil
        errorMessage = nil
    }

    private func apply(plan: PlaybackPlan) {
        playbackPlan = plan
        media = plan.media
        // A plan is applied again on a quality change or a recovery, which is still the same playback.
        if trackerSession == nil, let mediaServices {
            trackerSession = TrackerCoordinator.shared.beginPlayback(
                of: plan.media,
                detail: mediaServices.detail,
                resumeOffset: shouldResumeFromOffsetFlag ? plan.media.viewOffset : nil,
            )
        }
        playbackURL = plan.url
        playbackHTTPHeaders = plan.httpHeaders
        selectedQuality = plan.requestedQuality
        qualityFallbackMessage = plan.qualityFallbackMessage
        preferredAudioStreamFFIndex = plan.selectedAudioIndex
        preferredSubtitleStreamID = plan.selectedSubtitleIndex
        preferredSubtitleSelectionIsOff = plan.subtitleSelectionIsOff
        chapters = plan.chapters
        markers = plan.skipSegments
        scrubThumbnailSource = plan.scrubThumbnailSource
        serverAccessRecoveryError = nil
        errorMessage = nil
    }

    private func reportTimeline(state: TimelineState, force: Bool = false) {
        guard liveSession != nil || (mediaServices != nil && playbackPlan != nil) || hasProgressRecorder else { return }
        let now = Date()
        let stateChanged = lastTimelineState != state
        let intervalElapsed = lastTimelineSentAt.map {
            now.timeIntervalSince($0) >= timelineInterval
        } ?? true
        guard force || stateChanged || intervalElapsed else { return }

        lastTimelineSentAt = now
        lastTimelineState = state

        #if !os(tvOS)
            if let progressRecorder {
                guard state != .buffering else { return }
                progressRecorder.record(
                    position: position,
                    duration: duration ?? media?.duration,
                    isPaused: state == .paused,
                )
                return
            }
        #endif

        if let liveSession {
            guard !isLiveReportingSuspended else { return }
            if liveTimelineTask != nil {
                pendingLiveTimelineState = state
                return
            }
            startLiveTimelineReport(
                session: liveSession,
                generation: liveSessionGeneration,
                state: state,
            )
            return
        }

        Task { await sendTimeline(state: state) }
    }

    /// Buffering is neither a pause nor a resume for a tracker.
    private func reportTrackerState() {
        switch playbackState {
        case .playing:
            trackerSession?.playing(position: position, duration: duration ?? media?.duration)
        case .paused:
            trackerSession?.paused(position: position, duration: duration ?? media?.duration)
        case .buffering:
            break
        }
    }

    private var hasProgressRecorder: Bool {
        #if os(tvOS)
            false
        #else
            progressRecorder != nil
        #endif
    }

    private func startLiveTimelineReport(
        session: any LiveTVPlaybackSession,
        generation: Int,
        state: TimelineState,
    ) {
        liveTimelineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishLiveTimelineReport(generation: generation) }
            guard liveSessionGeneration == generation, !isLiveReportingSuspended else { return }
            do {
                let captureRange = try await session.report(
                    position: position,
                    isPaused: state == .paused,
                )
                guard liveSessionGeneration == generation else { return }
                liveCaptureRange = captureRange
            } catch {
                guard liveSessionGeneration == generation,
                      !Task.isCancelled,
                      !error.isCancellation
                else { return }
                ErrorReporter.capture(error)
            }
        }
    }

    private func finishLiveTimelineReport(generation: Int) {
        guard liveSessionGeneration == generation else { return }
        liveTimelineTask = nil
        guard let pendingState = pendingLiveTimelineState,
              let liveSession,
              !isLiveReportingSuspended
        else { return }
        pendingLiveTimelineState = nil
        startLiveTimelineReport(session: liveSession, generation: generation, state: pendingState)
    }

    private func adoptLiveSession(_ session: any LiveTVPlaybackSession) {
        invalidateLiveReporting()
        liveSession = session
        recordWatchedChannel(session.channel)
    }

    private func recordWatchedChannel(_ channel: LiveTVChannel) {
        liveWatchTask?.cancel()
        let store = mediaServices?.liveTVStore
        liveWatchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(LiveTVRecentChannels.watchThreshold))
            guard !Task.isCancelled, let self, liveChannel?.identity == channel.identity, liveSession != nil
            else { return }
            store?.recordWatched(channel.identity)
        }
    }

    private func invalidateLiveReporting() {
        liveSessionGeneration += 1
        liveTimelineTask?.cancel()
        liveTimelineTask = nil
        pendingLiveTimelineState = nil
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
                    currentSelection: currentPlaybackStreamSelection,
                )
            } else {
                try await mediaServices.playback.reportStarted(
                    plan: playbackPlan,
                    position: position,
                    isPaused: state == .paused,
                    currentSelection: currentPlaybackStreamSelection,
                )
                didReportPlaybackStarted = true
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            serverAccessRecoveryError = mediaServices.playback.serverAccessRecoveryError(from: error)
            ErrorReporter.capture(error)
        }
    }

    func resetRememberedTrackSelections() {
        guard let mediaServices, let media,
              let coordinator = mediaServices.trackSelectionCoordinator
        else { return }
        coordinator.reset(
            for: media,
            server: mediaServices.identity,
            accountIdentifier: mediaServices.trackSelectionAccountIdentifier ?? "default",
        )
    }

    private var rememberedTrackPreference: MediaTrackPreference? {
        guard let mediaServices, let media,
              let coordinator = mediaServices.trackSelectionCoordinator
        else { return nil }
        return coordinator.preference(
            for: media,
            server: mediaServices.identity,
            accountIdentifier: mediaServices.trackSelectionAccountIdentifier ?? "default",
        )
    }

    private var currentPlaybackStreamSelection: PlaybackStreamSelection? {
        guard !isLivePlayback,
              !isLocalPlayback,
              mediaServices?.trackSelectionCoordinator?.isEnabled == true
        else { return nil }
        return PlaybackStreamSelection(
            audioStreamIndex: preferredAudioStreamFFIndex,
            subtitleStreamIndex: preferredSubtitleStreamID,
            subtitleIsOff: preferredSubtitleSelectionIsOff,
        )
    }

    private static func liveMedia(channel: LiveTVChannel, server: ServerIdentity) -> MediaItem {
        MediaItem(
            id: channel.providerID, identity: MediaIdentity(server: server, itemID: channel.providerID),
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

enum PlayerPlaybackError: LocalizedError {
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
