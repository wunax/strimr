import SwiftUI

struct PlayerTVView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlexAPIContext.self) private var context
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @State var viewModel: PlayerViewModel
    let onExit: () -> Void
    @State private var playerController = PlayerController()
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var automaticSkipFeedbackWorkItem: DispatchWorkItem?
    @State private var automaticSkipFeedbackMessage: String?
    @State private var isScrubbing = false
    @State private var videoFormatBadge: PlayerVideoFormatBadge?
    @State private var audioTracks: [PlayerTrack] = []
    @State private var subtitleTracks: [PlayerTrack] = []
    @State private var settingsAudioTracks: [PlaybackSettingsTrack] = []
    @State private var settingsSubtitleTracks: [PlaybackSettingsTrack] = []
    @State private var selectedAudioTrackID: Int?
    @State private var selectedSubtitleTrackID: Int?
    @State private var pendingRecoveryAudioPlexStreamID: Int?
    @State private var pendingRecoverySubtitlePlexStreamID: Int?
    @State private var shouldRestoreTracksAfterLoad = false
    @State private var playbackRate: Float = 1.0
    @State private var appliedPreferredAudio = false
    @State private var appliedPreferredSubtitle = false
    @State private var appliedResumeOffset = false
    @State private var awaitingMediaLoad = false
    @State private var timelinePosition = 0.0
    @State private var isShowingChapterTray = false
    @State private var activeSettingsSheet: PlayerSettingsSheet?
    @State private var seekFeedback: SeekFeedback?
    @State private var seekFeedbackWorkItem: DispatchWorkItem?
    @State private var showingTerminationAlert = false
    @State private var terminationAlertMessage = ""
    @State private var subtitleSearchErrorMessage = ""
    @State private var showingSubtitleSearchError = false
    @State private var activePlaybackURL: URL?
    @State private var needsPlaybackReloadAfterBackground = false
    @State private var backgroundPlaybackPosition: Double?
    @State private var wasPlayingBeforeBackground = false
    @State private var shouldResumeAfterMediaLoad = false
    @State private var shouldPauseAfterMediaLoad = false
    @State private var isRecoveringServerAccess = false
    @State private var isShowingServerRecoveryAlert = false
    @State private var serverRecoveryError: PlexServerAccessRecoveryError?
    @State private var lastReloadedServerAccessGeneration = -1
    @FocusState private var focusedPlayerSurface: PlayerFocusTarget?

    private let controlsHideDelay: TimeInterval = 3.0
    private let seekFeedbackDelay: TimeInterval = 1.2

    private var seekBackwardInterval: Double {
        Double(settingsManager.playback.seekBackwardSeconds)
    }

    private var seekForwardInterval: Double {
        Double(settingsManager.playback.seekForwardSeconds)
    }

    init(
        viewModel: PlayerViewModel,
        onExit: @escaping () -> Void,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onExit = onExit
    }

    var body: some View {
        configuredPlayerView
    }

    private var configuredPlayerView: some View {
        let base = AnyView(
            playerScene
                .overlay {
                    playerOverlay
                },
        )

        let lifecycle = AnyView(
            base
                .onAppear {
                    playerController.onMediaLoaded = handleMediaLoaded
                    playerController.onPlaybackEnded = handlePlaybackEnded
                    showControls(temporarily: true)
                    playerController.setPlaybackRate(playbackRate)
                    if sharePlayCoordinator.isInSession {
                        sharePlayCoordinator.attachPlayer(
                            playerController,
                            ratingKey: viewModel.currentRatingKey,
                        )
                    }
                    startPlaybackIfNeeded(url: viewModel.playbackURL)
                }
                .onDisappear {
                    viewModel.handleStop()
                    hideControlsWorkItem?.cancel()
                    automaticSkipFeedbackWorkItem?.cancel()
                    seekFeedbackWorkItem?.cancel()
                    playerController.stop()
                    if sharePlayCoordinator.isInSession {
                        sharePlayCoordinator.leave()
                    }
                    sharePlayCoordinator.detachPlayer(playerController)
                }
                .onPlayPauseCommand {
                    togglePlayPause()
                }
                .onExitCommand {
                    if isShowingChapterTray {
                        withAnimation(.easeInOut) {
                            isShowingChapterTray = false
                        }
                        showControls(temporarily: true)
                        return
                    }
                    if sharePlayCoordinator.isInSession {
                        sharePlayCoordinator.leave()
                    }
                    dismissPlayer(force: true)
                }
                .task {
                    await viewModel.load()
                },
        )

        let playbackStateObservers = AnyView(
            lifecycle
                .onChange(of: viewModel.playbackURL) { _, newURL in
                    startPlaybackIfNeeded(url: newURL)
                }
                .onChange(of: playerController.isPaused) { _, _ in
                    syncPlaybackState()
                }
                .onChange(of: playerController.isBuffering) { _, _ in
                    syncPlaybackState()
                }
                .onChange(of: playerController.position) { _, newValue in
                    viewModel.handlePlaybackPosition(newValue, isScrubbing: isScrubbing)
                    handleAutomaticMarkerSkipIfNeeded()
                }
                .onChange(of: playerController.duration) { _, newValue in
                    viewModel.handlePlaybackDuration(newValue)
                }
                .onChange(of: playerController.bufferedAhead) { _, newValue in
                    viewModel.handleBufferedAhead(newValue)
                }
                .onChange(of: playerController.videoFormatBadge) { _, newValue in
                    videoFormatBadge = newValue
                },
        )

        let playbackObservers = AnyView(
            playbackStateObservers
                .onChange(of: playerController.errorMessage) { _, newValue in
                    guard let newValue else { return }
                    Task { await handlePlaybackError(newValue) }
                }
                .onChange(of: controlsVisible) { _, isVisible in
                    if isVisible {
                        focusedPlayerSurface = nil
                        return
                    }

                    focusHiddenControlsTarget(hasSkipOverlay: viewModel.activeSkipMarker != nil)
                }
                .onChange(of: viewModel.activeSkipMarker != nil) { _, hasSkipOverlay in
                    guard !controlsVisible else { return }
                    focusHiddenControlsTarget(hasSkipOverlay: hasSkipOverlay)
                }
                .onChange(of: viewModel.position) { _, newValue in
                    guard !isScrubbing else { return }
                    timelinePosition = newValue
                }
                .onChange(of: timelinePosition) { _, newValue in
                    guard isScrubbing else { return }
                    playerController.updateScrubPreview(to: newValue)
                }
                .onChange(of: viewModel.hasNavigableChapters) { _, hasChapters in
                    if !hasChapters {
                        isShowingChapterTray = false
                    }
                }
                .onChange(of: viewModel.terminationMessage) { _, newValue in
                    guard let newValue else { return }
                    terminationAlertMessage = newValue
                    showingTerminationAlert = true
                    playerController.pause()
                }
                .onChange(of: viewModel.serverAccessGeneration) { _, generation in
                    Task { await reloadPlaybackAfterServerAccessChange(generation) }
                }
                .onChange(of: viewModel.serverAccessRecoveryError) { _, error in
                    guard let error else { return }
                    presentServerRecoveryError(error)
                }
                .onChange(of: scenePhase) { _, newValue in
                    handleScenePhaseChange(newValue)
                },
        )

        let sessionObservers = AnyView(
            playbackObservers
                .onChange(of: sharePlayCoordinator.activityChangeID) { _, _ in
                    guard let activity = sharePlayCoordinator.activity,
                          activity.ratingKey != viewModel.currentRatingKey
                    else { return }
                    Task { await startPlayback(for: activity) }
                },
        )

        return sessionObservers
            .sheet(item: $activeSettingsSheet) { sheet in
                playbackSettingsSheet(sheet)
            }
            .alert("player.termination.title", isPresented: $showingTerminationAlert) {
                Button("player.termination.dismiss") {
                    dismissPlayer()
                }
            } message: {
                Text(terminationAlertMessage)
            }
            .alert("subtitles.search.activation.error", isPresented: $showingSubtitleSearchError) {
                Button("common.actions.done", role: .cancel) {}
            } message: {
                Text(subtitleSearchErrorMessage)
            }
            .alert("player.serverRecovery.title", isPresented: $isShowingServerRecoveryAlert) {
                Button("common.actions.retry") {
                    Task { await retryServerAccessRecovery() }
                }
                Button("player.serverRecovery.exitPlayer") {
                    Task { await exitAfterServerAccessFailure() }
                }
            } message: {
                Text(serverRecoveryMessage)
            }
    }

    private var playerScene: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerSurfaceView(controller: playerController)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            SubtitleOverlayView(
                cues: playerController.subtitleCues,
                currentTime: playerController.sourcePosition,
                maxCueDuration: playerController.subtitleMaxCueDuration,
                appearance: settingsManager.playback.subtitleAppearance,
                bottomPadding: subtitleBottomPadding,
                videoSize: playerController.sourceVideoSize,
                assRenderer: playerController.assRenderer,
                assReloadSignal: playerController.assReloadSignal,
                activeSubtitleCodec: playerController.activeSubtitleCodec,
            )
            .ignoresSafeArea()
        }
    }

    private var subtitleBottomPadding: CGFloat {
        guard controlsVisible else { return 48 }
        return isShowingChapterTray ? 520 : 380
    }

    private var playerOverlay: some View {
        let activeMarker = viewModel.activeSkipMarker
        let skipTitle = skipTitle(for: activeMarker)
        let hasSkipOverlay = activeMarker != nil

        return ZStack {
            if !controlsVisible, !hasSkipOverlay {
                Color.clear
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($focusedPlayerSurface, equals: .controlsProxy)
                    .onTapGesture {
                        showControls(temporarily: true)
                    }
                    .onMoveCommand { direction in
                        handleMoveCommand(direction)
                    }
            }

            if viewModel.isBuffering || isRecoveringServerAccess {
                bufferingOverlay
            }

            if controlsVisible {
                PlayerControlsTVView(
                    media: viewModel.media,
                    isPaused: viewModel.isPaused,
                    videoResolution: viewModel.media?.playbackResolutionLabel,
                    videoFormatBadge: videoFormatBadge,
                    position: timelineBinding,
                    duration: viewModel.duration,
                    bufferedAhead: viewModel.bufferedAhead,
                    bufferBasePosition: viewModel.position,
                    playbackRate: playbackRate,
                    showsEndsAtTime: settingsManager.playback.showEndsAtTime,
                    showsClock: settingsManager.playback.showClock,
                    isScrubbing: isScrubbing,
                    onShowAudioSettings: showAudioSettings,
                    onShowSubtitleSettings: showSubtitleSettings,
                    onShowSpeedSettings: showSpeedSettings,
                    chapters: viewModel.chapters,
                    showsChaptersOnTimeline: settingsManager.playback.showChaptersOnTimeline,
                    scrubPreview: playerController.scrubPreview,
                    currentPosition: viewModel.position,
                    isShowingChapterTray: isShowingChapterTray,
                    chapterImageURL: { chapter in
                        viewModel.chapterImageURL(for: chapter, width: 640, height: 360)
                    },
                    onShowChapters: showChapters,
                    onHideChapters: hideChapters,
                    onSelectChapter: selectChapter(_:),
                    onSeekBackward: { jump(by: -seekBackwardInterval) },
                    onPlayPause: togglePlayPause,
                    onSeekForward: { jump(by: seekForwardInterval) },
                    seekBackwardSeconds: settingsManager.playback.seekBackwardSeconds,
                    seekForwardSeconds: settingsManager.playback.seekForwardSeconds,
                    onScrubbingChanged: handleScrubbing(editing:),
                    skipMarkerTitle: skipTitle,
                    onSkipMarker: activeMarker.map { marker in
                        { skipMarker(to: marker) }
                    },
                    onUserInteraction: { showControls(temporarily: true) },
                    isSharePlay: sharePlayCoordinator.isInSession,
                )
                .transition(.opacity)
            }

            if !controlsVisible, let activeMarker, let skipTitle {
                skipOverlay(marker: activeMarker, title: skipTitle)
                    .onMoveCommand { direction in
                        handleSkipOverlayMoveCommand(direction)
                    }
            }

            if let seekFeedback {
                seekFeedbackOverlay(seekFeedback)
            }

            if let automaticSkipFeedbackMessage {
                AutomaticSkipFeedbackView(message: automaticSkipFeedbackMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, controlsVisible ? 330 : 48)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func playbackSettingsSheet(_ sheet: PlayerSettingsSheet) -> some View {
        switch sheet {
        case .audio:
            PlayerTrackSelectionView(
                titleKey: sheet.titleKey,
                tracks: settingsAudioTracks,
                selectedTrackID: selectedAudioTrackID,
                showOffOption: false,
                onSelect: selectAudioTrack(_:),
                onClose: { activeSettingsSheet = nil },
            )
        case .subtitle:
            PlayerTrackSelectionView(
                titleKey: sheet.titleKey,
                tracks: settingsSubtitleTracks,
                selectedTrackID: selectedSubtitleTrackID,
                showOffOption: true,
                onSelect: selectSubtitleTrack(_:),
                onSearchSubtitles: viewModel.canSearchSubtitles
                    ? { activeSettingsSheet = .subtitleSearch }
                    : nil,
                onClose: { activeSettingsSheet = nil },
            )
        case .speed:
            PlayerSpeedSelectionView(
                selectedRate: playbackRate,
                onSelect: selectPlaybackRate(_:),
                onClose: { activeSettingsSheet = nil },
            )
        case .subtitleSearch:
            SubtitleSearchView(
                ratingKey: viewModel.currentRatingKey,
                titlePlaceholder: viewModel.subtitleSearchTitlePlaceholder,
                context: context,
                onAttached: handleAttachedSubtitle(_:),
            )
        }
    }

    private var bufferingOverlay: some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)

                Text("player.status.buffering")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.bottom, 20)
    }

    private var timelineBinding: Binding<Double> {
        Binding(
            get: { timelinePosition },
            set: { timelinePosition = $0 },
        )
    }

    private func skipTitle(for marker: PlexMarker?) -> String? {
        marker.map {
            $0.isCredits
                ? String(localized: "player.skip.credits")
                : String(localized: "player.skip.intro")
        }
    }

    private func togglePlayPause() {
        playerController.togglePlayback()
        showControls(temporarily: true)
    }

    private func showAudioSettings() {
        refreshTracks()
        activeSettingsSheet = .audio
        showControls(temporarily: true)
    }

    private func showSubtitleSettings() {
        refreshTracks()
        activeSettingsSheet = .subtitle
        showControls(temporarily: true)
    }

    private func showSpeedSettings() {
        activeSettingsSheet = .speed
        showControls(temporarily: true)
    }

    private func showChapters() {
        guard viewModel.hasNavigableChapters else { return }
        hideControlsWorkItem?.cancel()
        withAnimation(.easeInOut) {
            isShowingChapterTray = true
            controlsVisible = true
        }
    }

    private func hideChapters() {
        guard isShowingChapterTray else { return }
        withAnimation(.easeInOut) {
            isShowingChapterTray = false
        }
        showControls(temporarily: true)
    }

    private func selectChapter(_ chapter: PlexChapter) {
        playerController.seek(to: chapter.startTime)
        viewModel.position = chapter.startTime
        timelinePosition = chapter.startTime
        withAnimation(.easeInOut) {
            isShowingChapterTray = false
        }
        showControls(temporarily: true)
    }

    private func refreshTracks() {
        Task {
            let tracks = playerController.trackList()

            let audio = tracks.filter { $0.type == .audio }
            let subtitles = tracks.filter { $0.type == .subtitle }

            await MainActor.run {
                audioTracks = audio
                subtitleTracks = subtitles

                settingsAudioTracks = audio.map {
                    PlaybackSettingsTrack(
                        track: $0,
                        plexStream: viewModel.plexStream(forID: $0.plexStreamID),
                    )
                }

                settingsSubtitleTracks = subtitles.map {
                    PlaybackSettingsTrack(
                        track: $0,
                        plexStream: viewModel.plexStream(forID: $0.plexStreamID),
                    )
                }

                if shouldRestoreTracksAfterLoad {
                    let audioID = pendingRecoveryAudioPlexStreamID.flatMap { plexStreamID in
                        audio.first { $0.plexStreamID == plexStreamID }?.id
                    }
                    let subtitleID = pendingRecoverySubtitlePlexStreamID.flatMap { plexStreamID in
                        subtitles.first { $0.plexStreamID == plexStreamID }?.id
                    }
                    selectedAudioTrackID = audioID
                    selectedSubtitleTrackID = subtitleID
                    playerController.selectAudioTrack(id: audioID)
                    playerController.selectSubtitleTrack(
                        id: subtitleID,
                        styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                    )
                    pendingRecoveryAudioPlexStreamID = nil
                    pendingRecoverySubtitlePlexStreamID = nil
                    shouldRestoreTracksAfterLoad = false
                } else {
                    applyPreferredTracksIfNeeded(audioTracks: audio, subtitleTracks: subtitles)

                    if selectedAudioTrackID == nil,
                       let activeAudio = audio.first(where: { $0.isSelected })?.id ?? audioTracks.first?.id
                    {
                        selectedAudioTrackID = activeAudio
                    }

                    if selectedSubtitleTrackID == nil,
                       let activeSubtitle = subtitles.first(where: { $0.isSelected })?.id
                    {
                        selectedSubtitleTrackID = activeSubtitle
                    }
                }
            }
        }
    }

    private func selectAudioTrack(_ id: Int?) {
        selectedAudioTrackID = id
        playerController.selectAudioTrack(id: id)

        guard
            let id,
            let track = audioTracks.first(where: { $0.id == id })
        else {
            return
        }

        Task {
            await viewModel.persistStreamSelection(for: track)
        }
    }

    private func selectSubtitleTrack(_ id: Int?) {
        selectedSubtitleTrackID = id
        playerController.selectSubtitleTrack(
            id: id,
            styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
        )

        Task {
            let track = id.flatMap { selectedID in
                subtitleTracks.first(where: { $0.id == selectedID })
            }
            await viewModel.persistSubtitleStreamSelection(for: track)
        }
    }

    private func selectPlaybackRate(_ rate: Float) {
        playbackRate = rate
        playerController.setPlaybackRate(rate)
        showControls(temporarily: true)
    }

    private func handleAttachedSubtitle(_: PlexSubtitleSearchResult) async {
        do {
            let subtitle = try await viewModel.refreshMetadataAfterSubtitleAttachment()
            let id = try playerController.registerExternalSubtitleIfNeeded(
                subtitle,
                styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
            )
            selectedSubtitleTrackID = id
            refreshTracks()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            subtitleSearchErrorMessage = error.localizedDescription
            showingSubtitleSearchError = true
        }
    }

    private func jump(by seconds: Double) {
        playerController.seek(by: seconds)
        showControls(temporarily: true)
    }

    private func quickSeek(by seconds: Double) {
        playerController.seek(by: seconds)
        showSeekFeedback(forward: seconds > 0, seconds: Int(abs(seconds)))
    }

    private func applyResumeOffsetIfNeeded() {
        guard !sharePlayCoordinator.isInSession else { return }
        guard viewModel.shouldResumeFromOffset else { return }
        guard !appliedResumeOffset, let offset = viewModel.resumePosition, offset > 0 else { return }
        appliedResumeOffset = true
        playerController.seek(to: offset)
    }

    private func handleMediaLoaded() {
        guard awaitingMediaLoad else { return }
        awaitingMediaLoad = false
        refreshTracks()
        if sharePlayCoordinator.isInSession {
            sharePlayCoordinator.playerDidLoad(ratingKey: viewModel.currentRatingKey)
        }
        applyResumeOffsetIfNeeded()
        if shouldPauseAfterMediaLoad {
            shouldPauseAfterMediaLoad = false
            shouldResumeAfterMediaLoad = false
            playerController.pause()
        } else if shouldResumeAfterMediaLoad {
            shouldResumeAfterMediaLoad = false
            playerController.resume()
        }
    }

    private func dismissPlayer(force _: Bool = false) {
        hideControlsWorkItem?.cancel()
        onExit()
    }

    private func handleScrubbing(editing: Bool) {
        isScrubbing = editing

        if editing {
            timelinePosition = viewModel.position
            playerController.beginScrubPreviewing(at: timelinePosition)
            hideControlsWorkItem?.cancel()
            withAnimation(.easeInOut) {
                controlsVisible = true
            }
        } else {
            playerController.endScrubPreviewing()
            playerController.seek(to: timelinePosition)
            viewModel.position = timelinePosition
            scheduleControlsHide()
        }
    }

    private func startPlaybackIfNeeded(url: URL?) {
        guard let url else { return }
        guard activePlaybackURL != url else { return }

        let startPosition = sharePlayCoordinator.activity?.initialPosition
            ?? (viewModel.shouldResumeFromOffset ? viewModel.resumePosition : nil)
        startPlayback(url: url, startPosition: startPosition, resetTrackSelection: true)
    }

    private func startPlayback(
        url: URL,
        startPosition: Double?,
        resetTrackSelection: Bool,
        shouldResumeAfterLoad: Bool = false,
        shouldPauseAfterLoad: Bool = false,
    ) {
        activePlaybackURL = url
        if resetTrackSelection {
            appliedPreferredAudio = false
            appliedPreferredSubtitle = false
            selectedAudioTrackID = nil
            selectedSubtitleTrackID = nil
        }
        appliedResumeOffset = startPosition != nil
        awaitingMediaLoad = true
        playerController.load(
            url: url,
            startPosition: startPosition,
            preferredAudioTrackID: viewModel.preferredAudioStreamFFIndex,
            losslessAudio: settingsManager.playback.losslessAudio,
            styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
            mediaIdentifier: viewModel.media?.id ?? url.lastPathComponent,
            plexStreamIDsByFFIndex: viewModel.plexStreamIDsByFFIndex(),
            externalSubtitles: viewModel.externalSubtitleTracks(),
            scrubThumbnailSource: viewModel.scrubThumbnailSource,
            showsScrubThumbnailPreviews: settingsManager.playback.showScrubThumbnailPreviews,
            generatesMissingScrubThumbnailPreviews:
            settingsManager.playback.generateMissingScrubThumbnailPreviews,
            autoplay: !sharePlayCoordinator.isInSession,
        )
        playerController.setPlaybackRate(playbackRate)
        shouldResumeAfterMediaLoad = shouldResumeAfterLoad
        shouldPauseAfterMediaLoad = shouldPauseAfterLoad
        showControls(temporarily: true)
    }

    private func handleScenePhaseChange(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .background:
            preparePlaybackForBackground()
        case .active:
            reloadPlaybackAfterBackgroundIfNeeded()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func preparePlaybackForBackground() {
        guard activePlaybackURL != nil, !needsPlaybackReloadAfterBackground else { return }

        backgroundPlaybackPosition = max(playerController.position, viewModel.position)
        wasPlayingBeforeBackground = !viewModel.isPaused
        needsPlaybackReloadAfterBackground = true
        playerController.stop()
        viewModel.handlePlaybackState(isPaused: true, isBuffering: false)
    }

    private func reloadPlaybackAfterBackgroundIfNeeded() {
        guard needsPlaybackReloadAfterBackground, let url = activePlaybackURL else { return }

        needsPlaybackReloadAfterBackground = false
        activePlaybackURL = nil
        let startPosition = backgroundPlaybackPosition ?? viewModel.position
        backgroundPlaybackPosition = nil
        startPlayback(
            url: url,
            startPosition: startPosition,
            resetTrackSelection: false,
            shouldResumeAfterLoad: wasPlayingBeforeBackground,
            shouldPauseAfterLoad: !wasPlayingBeforeBackground,
        )
        wasPlayingBeforeBackground = false
    }

    private func showControls(temporarily: Bool) {
        focusedPlayerSurface = nil

        withAnimation(.easeInOut) {
            controlsVisible = true
        }

        if temporarily, !isScrubbing, !isShowingChapterTray {
            scheduleControlsHide()
        } else {
            hideControlsWorkItem?.cancel()
        }
    }

    private func scheduleControlsHide() {
        hideControlsWorkItem?.cancel()
        guard !isShowingChapterTray else { return }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut) {
                controlsVisible = false
            }
        }

        hideControlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + controlsHideDelay, execute: workItem)
    }

    private func applyPreferredTracksIfNeeded(audioTracks: [PlayerTrack], subtitleTracks: [PlayerTrack]) {
        if !appliedPreferredAudio,
           let preferredAudioIndex = viewModel.preferredAudioStreamFFIndex,
           let track = audioTracks.first(where: { $0.ffIndex == preferredAudioIndex })
        {
            selectedAudioTrackID = track.id
            appliedPreferredAudio = true
        }

        if !appliedPreferredSubtitle,
           let preferredSubtitleStreamID = viewModel.preferredSubtitleStreamID,
           let track = subtitleTracks.first(where: { $0.plexStreamID == preferredSubtitleStreamID })
        {
            selectedSubtitleTrackID = track.id
            playerController.selectSubtitleTrack(
                id: track.id,
                styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
            )
            appliedPreferredSubtitle = true
        }
    }

    private func skipMarker(to marker: PlexMarker) {
        playerController.seek(to: marker.endTime)
        viewModel.position = marker.endTime
        timelinePosition = marker.endTime
        showControls(temporarily: true)
    }

    private func handleAutomaticMarkerSkipIfNeeded() {
        guard !isScrubbing, !sharePlayCoordinator.isInSession else { return }
        guard let marker = viewModel.automaticSkipMarker(
            autoSkipIntros: settingsManager.playback.autoSkipIntros,
            autoSkipCredits: settingsManager.playback.autoSkipCredits,
        ) else {
            return
        }

        playerController.seek(to: marker.endTime)
        viewModel.position = marker.endTime
        timelinePosition = marker.endTime
        showAutomaticSkipFeedback(for: marker)
    }

    private func showAutomaticSkipFeedback(for marker: PlexMarker) {
        automaticSkipFeedbackWorkItem?.cancel()
        let message = marker.isIntro
            ? String(localized: "player.skip.intro.automaticConfirmation")
            : String(localized: "player.skip.credits.automaticConfirmation")

        withAnimation(.easeInOut(duration: 0.2)) {
            automaticSkipFeedbackMessage = message
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                automaticSkipFeedbackMessage = nil
            }
        }
        automaticSkipFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    private func skipOverlay(marker: PlexMarker, title: String) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                SkipMarkerButton(title: title) {
                    skipMarker(to: marker)
                }
                .focused($focusedPlayerSurface, equals: .skipOverlay)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    private func focusHiddenControlsTarget(hasSkipOverlay: Bool) {
        let target: PlayerFocusTarget = hasSkipOverlay ? .skipOverlay : .controlsProxy
        DispatchQueue.main.async {
            guard !controlsVisible else { return }
            focusedPlayerSurface = target
        }
    }

    private func seekFeedbackOverlay(_ feedback: SeekFeedback) -> some View {
        VStack {
            Spacer()
            Image(systemName: feedback.systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 48)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1),
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(feedback.accessibilityText)
            Spacer()
        }
        .padding(.bottom, 120)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            showControls(temporarily: true)
        case .left:
            guard !controlsVisible else { return }
            quickSeek(by: -seekBackwardInterval)
        case .right:
            guard !controlsVisible else { return }
            quickSeek(by: seekForwardInterval)
        default:
            break
        }
    }

    private func handleSkipOverlayMoveCommand(_ direction: MoveCommandDirection) {
        handleMoveCommand(direction)

        guard !controlsVisible, viewModel.activeSkipMarker != nil else { return }

        DispatchQueue.main.async {
            guard !controlsVisible, viewModel.activeSkipMarker != nil else { return }
            focusedPlayerSurface = .skipOverlay
        }
    }

    private func showSeekFeedback(forward: Bool, seconds: Int) {
        let feedback = SeekFeedback(forward: forward, seconds: seconds)
        seekFeedbackWorkItem?.cancel()
        seekFeedback = feedback

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut) {
                seekFeedback = nil
            }
        }

        seekFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seekFeedbackDelay, execute: workItem)
    }

    private func handlePlaybackEnded() {
        guard let media = viewModel.media else {
            dismissPlayer()
            return
        }

        switch media.type {
        case .movie:
            Task {
                await handleMovieCompletion()
            }
        case .episode:
            Task {
                await handleEpisodeCompletion(for: media)
            }
        default:
            dismissPlayer()
        }
    }

    private func handleEpisodeCompletion(for _: MediaItem) async {
        await viewModel.markPlaybackFinished()

        guard sharePlayCoordinator.isInSession || settingsManager.playback.autoPlayNextEpisode else {
            await MainActor.run {
                dismissPlayer()
            }
            return
        }

        guard let nextEpisode = await viewModel.nextItemInQueue() else {
            await MainActor.run {
                dismissPlayer()
            }
            return
        }

        if sharePlayCoordinator.isInSession {
            await MainActor.run {
                sharePlayCoordinator.updateToNextEpisode(nextEpisode)
            }
            return
        }

        await startPlayback(of: nextEpisode)
    }

    private func handleMovieCompletion() async {
        await viewModel.markPlaybackFinished()

        guard let nextItem = await viewModel.nextItemInQueue() else {
            await MainActor.run {
                dismissPlayer()
            }
            return
        }

        await startPlayback(of: nextItem)
    }

    private func startPlayback(of episode: PlexItem) async {
        await MainActor.run {
            activePlaybackURL = nil
            viewModel = PlayerViewModel(
                playQueue: viewModel.playQueue,
                ratingKey: episode.ratingKey,
                context: context,
            )
        }

        await viewModel.load()
    }

    private func startPlayback(for activity: StrimrWatchActivity) async {
        await MainActor.run {
            activePlaybackURL = nil
            viewModel = PlayerViewModel(
                playQueue: viewModel.playQueue,
                ratingKey: activity.ratingKey,
                context: context,
                shouldResumeFromOffset: false,
            )
        }
        await viewModel.load()
    }

    private func syncPlaybackState() {
        viewModel.handlePlaybackState(
            isPaused: playerController.isPaused,
            isBuffering: playerController.isBuffering,
        )
    }

    private var serverRecoveryMessage: String {
        switch serverRecoveryError {
        case .accountUnauthorized:
            String(localized: "player.serverRecovery.accountUnauthorized")
        case .serverUnavailable:
            String(localized: "player.serverRecovery.serverUnavailable")
        case .connectionFailed, .none:
            String(localized: "player.serverRecovery.connectionFailed")
        }
    }

    private func handlePlaybackError(_ message: String) async {
        guard !isRecoveringServerAccess else { return }
        isRecoveringServerAccess = true
        defer { isRecoveringServerAccess = false }

        do {
            let recovered = try await viewModel.recoverServerAccessIfUnauthorized()
            guard recovered else {
                showPlaybackError(message)
                return
            }
        } catch let error as PlexServerAccessRecoveryError {
            presentServerRecoveryError(error)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            showPlaybackError(message)
        }
    }

    private func reloadPlaybackAfterServerAccessChange(_ generation: Int) async {
        guard !viewModel.isLocalPlayback,
              generation != lastReloadedServerAccessGeneration,
              activePlaybackURL != nil
        else { return }

        lastReloadedServerAccessGeneration = generation
        let position = max(playerController.position, viewModel.position)
        let wasPaused = playerController.isPaused
        pendingRecoveryAudioPlexStreamID = audioTracks.first {
            $0.id == selectedAudioTrackID
        }?.plexStreamID
        pendingRecoverySubtitlePlexStreamID = subtitleTracks.first {
            $0.id == selectedSubtitleTrackID
        }?.plexStreamID
        shouldRestoreTracksAfterLoad = true
        isRecoveringServerAccess = true
        playerController.stop()
        activePlaybackURL = nil

        do {
            let url = try await viewModel.refreshPlaybackSource()
            let isSharePlay = sharePlayCoordinator.isInSession
            startPlayback(
                url: url,
                startPosition: position,
                resetTrackSelection: false,
                shouldResumeAfterLoad: !isSharePlay && !wasPaused,
                shouldPauseAfterLoad: !isSharePlay && wasPaused,
            )
            isRecoveringServerAccess = false
        } catch let error as PlexServerAccessRecoveryError {
            isRecoveringServerAccess = false
            presentServerRecoveryError(error)
        } catch {
            isRecoveringServerAccess = false
            guard !Task.isCancelled, !error.isCancellation else { return }
            presentServerRecoveryError(.connectionFailed)
        }
    }

    private func retryServerAccessRecovery() async {
        guard !isRecoveringServerAccess else { return }
        isShowingServerRecoveryAlert = false
        isRecoveringServerAccess = true
        do {
            try await viewModel.forceServerAccessRecovery()
        } catch let error as PlexServerAccessRecoveryError {
            isRecoveringServerAccess = false
            presentServerRecoveryError(error)
        } catch {
            isRecoveringServerAccess = false
            guard !Task.isCancelled, !error.isCancellation else { return }
            presentServerRecoveryError(.connectionFailed)
        }
    }

    private func exitAfterServerAccessFailure() async {
        let error = serverRecoveryError
        activePlaybackURL = nil
        if sharePlayCoordinator.isInSession {
            sharePlayCoordinator.leave()
        }
        if let error {
            await sessionManager.handleTerminalServerAccessFailure(error)
        }
        dismissPlayer(force: true)
    }

    private func presentServerRecoveryError(_ error: PlexServerAccessRecoveryError) {
        playerController.pause()
        serverRecoveryError = error
        viewModel.clearServerAccessRecoveryError()
        isShowingServerRecoveryAlert = true
    }

    private func showPlaybackError(_ message: String) {
        terminationAlertMessage = message
        showingTerminationAlert = true
        playerController.pause()
    }
}

private enum PlayerSettingsSheet: String, Identifiable {
    case audio
    case subtitle
    case speed
    case subtitleSearch

    var id: String {
        rawValue
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .audio:
            "player.settings.audio"
        case .subtitle:
            "player.settings.subtitles"
        case .speed:
            "player.settings.speed"
        case .subtitleSearch:
            "subtitles.search.title"
        }
    }
}

private struct SeekFeedback: Equatable {
    let forward: Bool
    let seconds: Int

    var accessibilityText: String {
        if forward {
            return String(localized: "player.controls.skipForwardSeconds \(seconds)")
        }
        return String(localized: "player.controls.rewindSeconds \(seconds)")
    }

    var systemImage: String {
        let supported = [5, 10, 15, 30, 45, 60]
        let prefix = forward ? "goforward" : "gobackward"
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
}

private enum PlayerFocusTarget: Hashable {
    case controlsProxy
    case skipOverlay
}
