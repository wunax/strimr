import SwiftUI

struct PlayerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
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
    @State private var pendingRecoveryAudioProviderStreamID: Int?
    @State private var pendingRecoverySubtitleProviderStreamID: Int?
    @State private var pendingRecoveryAudioTrackID: Int?
    @State private var pendingRecoverySubtitleTrackID: Int?
    @State private var shouldRestoreTracksAfterLoad = false
    @State private var playbackRate: Float = 1.0
    @State private var appliedPreferredAudio = false
    @State private var appliedPreferredSubtitle = false
    @State private var appliedResumeOffset = false
    @State private var awaitingMediaLoad = false
    @State private var timelinePosition = 0.0
    @State private var sheetPresentation = IsolatedSheetPresentation<PlayerSettingsSheet>()
    @State private var isSearchingSubtitles = false
    @State private var settingsControl: PlayerSettingsControl?
    @State private var settingsMenuFocusID: String?
    @State private var settingsFocusGeneration = 0
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
    @State private var isShowingInfoPanel = false
    @State private var infoPanelTab = PlayerInfoTab.info
    @State private var serverRecoveryError: MediaServerAccessRecoveryError?
    @State private var lastReloadedServerAccessGeneration = -1
    @State private var nextEpisodePresentation = NextEpisodePresentation()
    @State private var sleepTimer = SleepTimer()
    @State private var pauseScreen = PauseScreenPresentation()
    @State private var qualityNoticeMessage: String?
    @State private var activeOffsetBar: PlaybackOffsetKind?
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
                        .disabled(sheetPresentation.item != nil || activeOffsetBar != nil)
                        .accessibilityHidden(sheetPresentation.item != nil)
                        .opacity(sheetPresentation.item != nil ? 0 : 1)
                }
                .overlay(alignment: .bottom) {
                    infoPanelOverlay
                },
        )

        let lifecycle = AnyView(
            base
                .onAppear {
                    guard activePlaybackURL == nil else { return }
                    playerController.onMediaLoaded = handleMediaLoaded
                    playerController.onPlaybackEnded = handlePlaybackEnded
                    configureSleepTimer()
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
                    guard !isSearchingSubtitles else { return }
                    nextEpisodePresentation.cancel()
                    sleepTimer.cancel()
                    pauseScreen.cancel()
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
                    handleExitCommand()
                }
                .task {
                    guard activePlaybackURL == nil else { return }
                    await viewModel.load(quality: settingsManager.playback.qualityPreset)
                },
        )

        let playbackStateObservers = AnyView(
            lifecycle
                .onChange(of: viewModel.playbackURL) { _, newURL in
                    startPlaybackIfNeeded(url: newURL)
                }
                .onChange(of: playerController.isPaused) { _, isPaused in
                    syncPlaybackState()
                    sleepTimer.handlePlaybackStateChange(isPaused: isPaused)
                }
                .onChange(of: playerController.isBuffering) { _, _ in
                    syncPlaybackState()
                }
                .onChange(of: playerController.position) { _, newValue in
                    viewModel.handlePlaybackPosition(newValue, isScrubbing: isScrubbing)
                    handleAutomaticMarkerSkipIfNeeded()
                    sleepTimer.handlePosition(
                        newValue,
                        duration: playerController.duration ?? viewModel.duration,
                        chapters: viewModel.chapters,
                    )
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
                    if nextEpisodePresentation.isPresented || sleepTimer.isPromptPresented {
                        focusedPlayerSurface = nil
                        return
                    }

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
                .onChange(of: nextEpisodePresentation.isPresented) { _, isPresented in
                    guard isPresented else { return }

                    hideInfoPanel()
                    hideControlsWorkItem?.cancel()
                    focusedPlayerSurface = nil
                    withAnimation(.easeInOut) {
                        controlsVisible = false
                    }
                }
                .onChange(of: sleepTimer.isPromptPresented) { _, isPresented in
                    if isPresented {
                        if activeOffsetBar != nil {
                            closeOffsetBar()
                        }
                        sheetPresentation.item = nil
                        hideInfoPanel()
                        hideControlsWorkItem?.cancel()
                        focusedPlayerSurface = nil
                        withAnimation(.easeInOut) {
                            controlsVisible = false
                        }
                    } else {
                        showControls(temporarily: true)
                    }
                }
                .onChange(of: isPauseScreenEligible, initial: true) { _, isEligible in
                    pauseScreen.update(isEligible: isEligible)
                }
                .onChange(of: pauseScreen.isPresented) { _, isPresented in
                    guard isPresented else { return }
                    hideControlsWorkItem?.cancel()
                    withAnimation(.easeInOut) {
                        controlsVisible = false
                    }
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
                    if !hasChapters, infoPanelTab == .chapters {
                        infoPanelTab = .info
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
                }
                .onChange(of: sharePlayCoordinator.isInSession) { _, isInSession in
                    if isInSession {
                        sleepTimer.cancel()
                    }
                },
        )

        return sessionObservers
            .overlay {
                if let sheet = sheetPresentation.item {
                    TVContextPanelView {
                        playbackSettingsSheet(sheet)
                            .id(sheet)
                    }
                    .onExitCommand { navigateBackInSettingsPanel() }
                    .onPlayPauseCommand { togglePlayPause() }
                }
            }
            .overlay {
                if let activeOffsetBar {
                    offsetBar(activeOffsetBar)
                }
            }
            .taskPresentation(isPresented: $isSearchingSubtitles, onDismiss: {
                refreshTracks()
            }) {
                playbackSettingsSheet(.subtitleSearch)
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
            .alert(
                "player.settings.quality",
                isPresented: Binding(
                    get: { qualityNoticeMessage != nil },
                    set: {
                        if !$0 {
                            qualityNoticeMessage = nil
                        }
                    },
                ),
            ) {
                Button("common.actions.done") { qualityNoticeMessage = nil }
            } message: {
                Text(qualityNoticeMessage ?? "")
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
                currentTime: playerController.subtitlePosition,
                maxCueDuration: playerController.subtitleMaxCueDuration,
                appearance: settingsManager.playback.subtitleAppearance,
                bottomPadding: subtitleBottomPadding,
                videoSize: playerController.sourceVideoSize,
                assRenderer: playerController.assRenderer,
                assReloadSignal: playerController.assReloadSignal,
                activeSubtitleCodec: playerController.activeSubtitleCodec,
            )
            .ignoresSafeArea()
            .opacity(pauseScreen.isPresented ? 0 : 1)
        }
    }

    private var subtitleBottomPadding: CGFloat {
        guard controlsVisible else { return 48 }
        return isShowingInfoPanel ? 440 : 380
    }

    private var playerOverlay: some View {
        let activeMarker = viewModel.activeSkipMarker
        let skipTitle = skipTitle(for: activeMarker)
        let hasSkipOverlay = activeMarker != nil

        return ZStack {
            if !controlsVisible, !isShowingInfoPanel, !hasSkipOverlay, !sleepTimer.isPromptPresented {
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

            if controlsVisible, !isShowingInfoPanel {
                PlayerControlsView(
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
                    onShowSettings: showSettings,
                    sleepTimer: sleepTimer,
                    chapters: viewModel.chapters,
                    showsChaptersOnTimeline: settingsManager.playback.showChaptersOnTimeline,
                    scrubPreview: playerController.scrubPreview,
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
                    hasInfoPanel: canShowInfoPanel,
                    onShowInfoPanel: showInfoPanel,
                    isLive: viewModel.isLivePlayback,
                    behindLiveSeconds: playerController.behindLiveSeconds,
                    onGoLive: playerController.seekToLiveEdge,
                    canSwitchPreviousChannel: viewModel.canSwitchToPreviousLiveChannel,
                    canSwitchNextChannel: viewModel.canSwitchToNextLiveChannel,
                    onPreviousChannel: { switchLiveChannel(by: -1) },
                    onNextChannel: { switchLiveChannel(by: 1) },
                    settingsControl: settingsControl,
                    showsSubtitleOffsetIndicator: playerController.subtitleDelayMilliseconds != 0,
                    settingsFocusGeneration: settingsFocusGeneration,
                )
                .transition(.opacity)
            }

            if !controlsVisible, !isShowingInfoPanel, let activeMarker, let skipTitle {
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

            if pauseScreen.isPresented, let media = viewModel.media {
                PauseScreenOverlay(
                    media: media,
                    position: viewModel.position,
                    duration: viewModel.duration,
                    playbackRate: playbackRate,
                    showsEndsAtTime: settingsManager.playback.showEndsAtTime,
                    isLive: viewModel.isLivePlayback,
                )
                .transition(.opacity)
            }

            if nextEpisodePresentation.isPresented,
               let services = viewModel.artworkServices
            {
                NextEpisodeOverlay(
                    presentation: nextEpisodePresentation,
                    services: services,
                    onPlay: { nextViewModel in
                        await startPlayback(using: nextViewModel)
                    },
                    onClose: { dismissPlayer(force: true) },
                )
            }

            if sleepTimer.isPromptPresented {
                SleepTimerPromptOverlay(sleepTimer: sleepTimer)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: pauseScreen.isPresented)
    }

    @ViewBuilder
    private var infoPanelOverlay: some View {
        if isShowingInfoPanel, let media = viewModel.media {
            PlayerInfoPanelView(
                media: media,
                services: viewModel.artworkServices,
                queueItems: viewModel.queueItems,
                queueCurrentIndex: viewModel.queueCurrentIndex ?? 0,
                showsQueue: showsQueueTab,
                chapters: viewModel.chapters,
                currentPosition: viewModel.position,
                selectedTab: $infoPanelTab,
                onSelectQueueItem: selectQueueItem(at:),
                onSelectChapter: selectChapter(_:),
                onClose: hideInfoPanel,
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onExitCommand(perform: hideInfoPanel)
        }
    }

    private var canShowInfoPanel: Bool {
        viewModel.media != nil && !viewModel.isLivePlayback
    }

    private var showsQueueTab: Bool {
        viewModel.hasNavigableQueue && viewModel.artworkServices != nil
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
                syncItem: playerController.offsetMenuItem(.audio, burnsSubtitles: viewModel.burnsSubtitles),
                onSelectSync: openOffsetBar(_:),
                onClose: closeSettingsPanel,
            )
        case .subtitle:
            PlayerTrackSelectionView(
                titleKey: sheet.titleKey,
                tracks: settingsSubtitleTracks,
                selectedTrackID: selectedSubtitleTrackID,
                showOffOption: true,
                onSelect: selectSubtitleTrack(_:),
                onSearchSubtitles: viewModel.canSearchSubtitles
                    ? { isSearchingSubtitles = true }
                    : nil,
                onResetTrackSelections: viewModel.canResetRememberedTrackSelections
                    ? { viewModel.resetRememberedTrackSelections() }
                    : nil,
                syncItem: playerController.offsetMenuItem(.subtitles, burnsSubtitles: viewModel.burnsSubtitles),
                onSelectSync: openOffsetBar(_:),
                onClose: closeSettingsPanel,
            )
        case .speed:
            PlayerSpeedSelectionView(
                selectedRate: playbackRate,
                onSelect: selectPlaybackRate(_:),
                onClose: closeSettingsPanel,
            )
        case .settings:
            PlayerSettingsMenuView(
                qualityTitle: viewModel.isLivePlayback ? nil : viewModel.selectedQuality.title,
                versionTitle: viewModel.showsVersionSelection
                    ? viewModel.versionOptions.first(where: \.isSelected)?.title ?? ""
                    : nil,
                sleepTimer: sleepTimer,
                mediaKind: viewModel.media?.type,
                initialOptionID: settingsMenuFocusID,
                onShowQuality: { sheetPresentation.item = .quality },
                onShowVersions: { sheetPresentation.item = .version },
                onShowSleepTimer: { sheetPresentation.item = .sleepTimer },
                onClose: closeSettingsPanel,
            )
        case .quality:
            PlayerQualitySelectionView(
                selectedQuality: viewModel.selectedQuality,
                onSelect: { selectQuality($0) },
                onClose: navigateBackInSettingsPanel,
            )
        case .version:
            PlayerVersionSelectionView(
                versions: viewModel.versionOptions,
                onSelect: selectVersion(_:),
                onClose: navigateBackInSettingsPanel,
            )
        case .sleepTimer:
            PlayerSleepTimerSelectionView(
                sleepTimer: sleepTimer,
                modes: SleepTimerMode.available(
                    isLive: viewModel.isLivePlayback,
                    hasChapters: viewModel.hasNavigableChapters,
                ),
                mediaKind: viewModel.media?.type,
                isAvailable: !sharePlayCoordinator.isInSession,
                onSelect: selectSleepTimer(_:),
                onClose: navigateBackInSettingsPanel,
            )
        case .subtitleSearch:
            if let services = viewModel.subtitleSearchServices {
                SubtitleSearchView(
                    itemID: viewModel.currentRatingKey,
                    titlePlaceholder: viewModel.subtitleSearchTitlePlaceholder,
                    services: services,
                    onAttached: handleAttachedSubtitle(_:),
                )
            }
        }
    }

    private func offsetBar(_ kind: PlaybackOffsetKind) -> some View {
        let alignment = PlayerOffsetBar.alignment(for: settingsManager.playback.subtitleVerticalPosition)
        let edge: Edge.Set = alignment == .top ? .top : .bottom
        let inset: CGFloat = alignment == .top || !controlsVisible ? 40 : 380
        return PlayerOffsetBar(
            controller: playerController,
            kind: kind,
            burnsSubtitles: viewModel.burnsSubtitles,
            onDone: closeOffsetBar,
        )
        .focusSection()
        .padding(edge, inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .transition(.opacity)
        .onExitCommand { closeOffsetBar() }
        .onPlayPauseCommand { togglePlayPause() }
    }

    private var timelineBinding: Binding<Double> {
        Binding(
            get: { timelinePosition },
            set: { timelinePosition = $0 },
        )
    }

    private func skipTitle(for marker: SkipSegment?) -> String? {
        marker.map {
            $0.isCredits
                ? String(localized: "player.skip.credits")
                : String(localized: "player.skip.intro")
        }
    }

    private func togglePlayPause() {
        if sleepTimer.isPromptPresented {
            sleepTimer.pauseNow()
            return
        }
        playerController.togglePlayback()
        showControls(temporarily: true)
    }

    private func showAudioSettings() {
        refreshTracks()
        settingsControl = .audio
        sheetPresentation.item = .audio
        showControls(temporarily: true)
    }

    private func showSubtitleSettings() {
        refreshTracks()
        settingsControl = .subtitle
        sheetPresentation.item = .subtitle
        showControls(temporarily: true)
    }

    private func showSpeedSettings() {
        settingsControl = .speed
        sheetPresentation.item = .speed
        showControls(temporarily: true)
    }

    private func showSettings() {
        settingsControl = .settings
        settingsMenuFocusID = nil
        sheetPresentation.item = .settings
        showControls(temporarily: true)
    }

    private func navigateBackInSettingsPanel() {
        guard let sheet = sheetPresentation.item, let parent = sheet.parent else {
            closeSettingsPanel()
            return
        }
        settingsMenuFocusID = sheet.rawValue
        sheetPresentation.item = parent
    }

    private func configureSleepTimer() {
        sleepTimer.pausePlayback = {
            nextEpisodePresentation.cancelCountdown()
            wasPlayingBeforeBackground = false
            playerController.pause()
        }
        sleepTimer.isPlaybackActive = {
            !playerController.isPaused
                && !nextEpisodePresentation.isPresented
                && !needsPlaybackReloadAfterBackground
        }
        sleepTimer.setVolumeAttenuation = { playerController.setVolumeAttenuation($0) }
        sleepTimer.onBoundaryPause = {
            showFeedbackMessage(String(localized: "player.sleepTimer.pausedFeedback"), duration: 5)
        }
    }

    private func selectSleepTimer(_ mode: SleepTimerMode?) {
        guard let mode else {
            sleepTimer.cancel()
            return
        }
        sleepTimer.start(mode)
        closeSettingsPanel()
        showFeedbackMessage(
            String(localized: "player.sleepTimer.confirmation \(mode.title(for: viewModel.media?.type))"),
        )
    }

    private func selectQuality(_ quality: TranscodeQualityPreset, force: Bool = false) {
        guard force || quality != viewModel.selectedQuality else { return }
        let position = max(playerController.position, viewModel.position)
        let wasPaused = playerController.isPaused
        Task {
            do {
                let url = try await viewModel.changeQuality(to: quality, force: force)
                activePlaybackURL = nil
                startPlayback(
                    url: url,
                    startPosition: position,
                    resetTrackSelection: true,
                    shouldResumeAfterLoad: !wasPaused,
                    shouldPauseAfterLoad: wasPaused,
                )
                qualityNoticeMessage = viewModel.qualityFallbackMessage
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
                qualityNoticeMessage = error.localizedDescription
            }
        }
    }

    private func selectVersion(_ versionID: String) {
        guard versionID != viewModel.currentVersionID else { return }
        let position = max(playerController.position, viewModel.position)
        let wasPaused = playerController.isPaused
        closeSettingsPanel()
        Task {
            do {
                let result = try await viewModel.changeVersion(to: versionID, from: position)
                activePlaybackURL = nil
                startPlayback(
                    url: result.url,
                    startPosition: result.position,
                    resetTrackSelection: true,
                    shouldResumeAfterLoad: !wasPaused,
                    shouldPauseAfterLoad: wasPaused,
                )
                qualityNoticeMessage = viewModel.qualityFallbackMessage
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
                qualityNoticeMessage = error.localizedDescription
            }
        }
    }

    private func openOffsetBar(_ kind: PlaybackOffsetKind) {
        sheetPresentation.item = nil
        hideControlsWorkItem?.cancel()
        withAnimation(.easeInOut) {
            activeOffsetBar = kind
            controlsVisible = true
        }
    }

    private func closeOffsetBar() {
        playerController.commitAudioDelay()
        withAnimation(.easeInOut) {
            activeOffsetBar = nil
        }
        settingsFocusGeneration += 1
        showControls(temporarily: true)
    }

    private func closeSettingsPanel() {
        sheetPresentation.item = nil
        settingsFocusGeneration += 1
        showControls(temporarily: true)
    }

    private func handleExitCommand() {
        if dismissPauseScreen() {
            return
        }
        if sleepTimer.isPromptPresented {
            sleepTimer.continueAfterPrompt()
            return
        }
        if activeOffsetBar != nil {
            closeOffsetBar()
            return
        }
        if sheetPresentation.item != nil {
            navigateBackInSettingsPanel()
            return
        }
        if nextEpisodePresentation.isPresented {
            nextEpisodePresentation.cancel()
            dismissPlayer(force: true)
            return
        }

        if isShowingInfoPanel {
            hideInfoPanel()
            return
        }

        if sharePlayCoordinator.isInSession {
            sharePlayCoordinator.leave()
        }
        dismissPlayer(force: true)
    }

    private func selectChapter(_ chapter: MediaChapter) {
        playerController.seek(to: chapter.startTime)
        viewModel.position = chapter.startTime
        timelinePosition = chapter.startTime
        hideInfoPanel()
    }

    private func showInfoPanel() {
        guard canShowInfoPanel else { return }

        hideControlsWorkItem?.cancel()
        focusedPlayerSurface = nil
        infoPanelTab = .info
        withAnimation(.easeInOut) {
            isShowingInfoPanel = true
        }
    }

    private func hideInfoPanel() {
        guard isShowingInfoPanel else { return }
        withAnimation(.easeInOut) {
            isShowingInfoPanel = false
        }
        DispatchQueue.main.async {
            showControls(temporarily: true)
        }
    }

    private func selectQueueItem(at index: Int) {
        guard let currentIndex = viewModel.queueCurrentIndex,
              index != currentIndex
        else {
            hideInfoPanel()
            return
        }

        guard let nextViewModel = viewModel.makePlayerViewModel(
            at: index,
            shouldResumeFromOffset: true,
        ) else { return }

        hideInfoPanel()
        Task {
            await startPlayback(using: nextViewModel)
        }
    }

    private func refreshTracks() {
        Task {
            let tracks = viewModel.isTranscoding
                ? viewModel.sourcePlayerTracks()
                : playerController.trackList()

            let audio = tracks.filter { $0.type == .audio }
            let subtitles = tracks.filter { $0.type == .subtitle }

            await MainActor.run {
                audioTracks = audio
                subtitleTracks = subtitles

                settingsAudioTracks = audio.map {
                    PlaybackSettingsTrack(
                        track: $0,
                        metadata: viewModel.trackMetadata(forID: $0.providerStreamID),
                    )
                }

                settingsSubtitleTracks = subtitles.map {
                    PlaybackSettingsTrack(
                        track: $0,
                        metadata: viewModel.trackMetadata(forID: $0.providerStreamID),
                    )
                }

                if shouldRestoreTracksAfterLoad {
                    let audioID = pendingRecoveryAudioProviderStreamID.flatMap { providerStreamID in
                        audio.first { $0.providerStreamID == providerStreamID }?.id
                    } ?? pendingRecoveryAudioTrackID
                    let subtitleID = pendingRecoverySubtitleProviderStreamID.flatMap { providerStreamID in
                        subtitles.first { $0.providerStreamID == providerStreamID }?.id
                    } ?? pendingRecoverySubtitleTrackID
                    selectedAudioTrackID = audioID
                    selectedSubtitleTrackID = subtitleID
                    playerController.selectAudioTrack(id: audioID)
                    playerController.selectSubtitleTrack(
                        id: subtitleID,
                        styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                    )
                    pendingRecoveryAudioProviderStreamID = nil
                    pendingRecoverySubtitleProviderStreamID = nil
                    pendingRecoveryAudioTrackID = nil
                    pendingRecoverySubtitleTrackID = nil
                    shouldRestoreTracksAfterLoad = false
                } else {
                    applyPreferredTracksIfNeeded(audioTracks: audio, subtitleTracks: subtitles)

                    if selectedAudioTrackID == nil,
                       let activeAudio = audio.first(where: { $0.isSelected })?.id ?? audioTracks.first?.id
                    {
                        selectedAudioTrackID = activeAudio
                    }

                    if viewModel.preferredSubtitleSelectionIsOff {
                        selectedSubtitleTrackID = nil
                        playerController.selectSubtitleTrack(
                            id: nil,
                            styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                        )
                    } else if selectedSubtitleTrackID == nil,
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

        guard
            let id,
            let track = audioTracks.first(where: { $0.id == id })
        else {
            return
        }

        Task {
            await viewModel.persistStreamSelection(for: track)
            if viewModel.isTranscoding {
                selectQuality(viewModel.selectedQuality, force: true)
            } else {
                playerController.selectAudioTrack(id: id)
            }
        }
    }

    private func selectSubtitleTrack(_ id: Int?) {
        if id != selectedSubtitleTrackID {
            playerController.setSubtitleDelay(milliseconds: 0)
        }
        selectedSubtitleTrackID = id
        Task {
            let track = id.flatMap { selectedID in
                subtitleTracks.first(where: { $0.id == selectedID })
            }
            await viewModel.persistSubtitleStreamSelection(for: track)
            if viewModel.isTranscoding {
                selectQuality(viewModel.selectedQuality, force: true)
            } else {
                playerController.selectSubtitleTrack(
                    id: id,
                    styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                )
            }
        }
    }

    private func selectPlaybackRate(_ rate: Float) {
        playbackRate = rate
        playerController.setPlaybackRate(rate)
        showControls(temporarily: true)
    }

    private func handleAttachedSubtitle(_: RemoteSubtitleResult) async {
        do {
            let subtitle = try await viewModel.refreshMetadataAfterSubtitleAttachment()
            let id = try playerController.registerExternalSubtitleIfNeeded(
                subtitle,
                styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
            )
            playerController.setSubtitleDelay(milliseconds: 0)
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
        let origin = playerController.seekOrigin
        playerController.seek(by: seconds)
        showSeekFeedback(.next(
            after: seekFeedback,
            forward: seconds > 0,
            origin: origin,
            target: playerController.seekOrigin,
        ))
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
        viewModel.confirmLiveChannelSwitch()
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
            pendingRecoveryAudioProviderStreamID = nil
            pendingRecoverySubtitleProviderStreamID = nil
            pendingRecoveryAudioTrackID = nil
            pendingRecoverySubtitleTrackID = nil
            shouldRestoreTracksAfterLoad = false
        }
        appliedResumeOffset = startPosition != nil
        awaitingMediaLoad = true
        let preferredAudioTrackID: Int? = if !resetTrackSelection, shouldRestoreTracksAfterLoad,
                                             !viewModel.isTranscoding
        {
            pendingRecoveryAudioProviderStreamID.flatMap {
                viewModel.ffIndex(forProviderStreamID: $0)
            } ?? pendingRecoveryAudioTrackID ?? viewModel.preferredAudioStreamFFIndex
        } else {
            viewModel.preferredAudioStreamFFIndex
        }
        playerController.load(
            url: url,
            httpHeaders: viewModel.playbackHTTPHeaders,
            startPosition: startPosition,
            preferredAudioTrackID: preferredAudioTrackID,
            losslessAudio: settingsManager.playback.losslessAudio,
            styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
            mediaIdentifier: viewModel.media?.id ?? url.lastPathComponent,
            providerStreamIDsByFFIndex: viewModel.providerStreamIDsByFFIndex(),
            externalSubtitles: viewModel.externalSubtitleTracks(),
            scrubThumbnailSource: viewModel.scrubThumbnailSource,
            showsScrubThumbnailPreviews: settingsManager.playback.showScrubThumbnailPreviews,
            generatesMissingScrubThumbnailPreviews:
            settingsManager.playback.generateMissingScrubThumbnailPreviews,
            isLive: viewModel.isLivePlayback,
            nativeRemoteHLS: viewModel.liveNativeRemoteHLS,
            dvrWindowSeconds: viewModel.liveDVRWindowSeconds,
            audioDelayMilliseconds: settingsManager.playback.audioDelayMilliseconds,
            autoplay: !sharePlayCoordinator.isInSession,
        )
        playerController.setPlaybackRate(playbackRate)
        shouldResumeAfterMediaLoad = shouldResumeAfterLoad
        shouldPauseAfterMediaLoad = shouldPauseAfterLoad
        showControls(temporarily: true)
    }

    private func switchLiveChannel(by offset: Int) {
        Task {
            do {
                let url = try await viewModel.switchLiveChannel(by: offset)
                playerController.stop()
                startPlayback(url: url, startPosition: nil, resetTrackSelection: true)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                LiveTVErrorReporting.capture(error)
                showPlaybackError(String(localized: "livetv.playback.error"))
            }
        }
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
        if viewModel.isLivePlayback {
            Task {
                if await viewModel.enterLiveBackground() {
                    dismissPlayer()
                }
            }
        }
        guard activePlaybackURL != nil, !needsPlaybackReloadAfterBackground else { return }

        backgroundPlaybackPosition = max(playerController.position, viewModel.position)
        wasPlayingBeforeBackground = !viewModel.isPaused
        captureTrackSelectionForReload()
        needsPlaybackReloadAfterBackground = true
        playerController.stop()
        viewModel.handlePlaybackState(isPaused: true, isBuffering: false)
    }

    private func reloadPlaybackAfterBackgroundIfNeeded() {
        viewModel.leaveLiveBackground()
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

    private func captureTrackSelectionForReload() {
        pendingRecoveryAudioTrackID = selectedAudioTrackID
        pendingRecoverySubtitleTrackID = selectedSubtitleTrackID
        pendingRecoveryAudioProviderStreamID = audioTracks.first {
            $0.id == selectedAudioTrackID
        }?.providerStreamID
        pendingRecoverySubtitleProviderStreamID = subtitleTracks.first {
            $0.id == selectedSubtitleTrackID
        }?.providerStreamID
        shouldRestoreTracksAfterLoad = true
    }

    private func showControls(temporarily: Bool) {
        pauseScreen.registerInteraction()
        guard !nextEpisodePresentation.isPresented, !sleepTimer.isPromptPresented else { return }

        focusedPlayerSurface = nil

        withAnimation(.easeInOut) {
            controlsVisible = true
        }

        if temporarily, !isScrubbing {
            scheduleControlsHide()
        } else {
            hideControlsWorkItem?.cancel()
        }
    }

    private var isPauseScreenEligible: Bool {
        settingsManager.playback.showInfoWhenPaused
            && playerController.isPaused
            && !playerController.isBuffering
            && viewModel.media != nil
            && !isScrubbing
            && !isVoiceOverEnabled
            && !isSearchingSubtitles
            && sheetPresentation.item == nil
            && !isShowingInfoPanel
            && activeOffsetBar == nil
            && viewModel.activeSkipMarker == nil
            && !nextEpisodePresentation.isPresented
            && !sleepTimer.isPromptPresented
            && !isRecoveringServerAccess
            && !showingTerminationAlert
            && !showingSubtitleSearchError
            && !isShowingServerRecoveryAlert
            && qualityNoticeMessage == nil
    }

    /// Returns whether the pause screen was visible, in which case the input only dismisses it.
    private func dismissPauseScreen() -> Bool {
        guard pauseScreen.registerInteraction() else { return false }
        showControls(temporarily: true)
        return true
    }

    private func scheduleControlsHide() {
        hideControlsWorkItem?.cancel()
        guard sheetPresentation.item == nil, activeOffsetBar == nil else { return }

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
           let track = subtitleTracks.first(where: { $0.providerStreamID == preferredSubtitleStreamID })
        {
            selectedSubtitleTrackID = track.id
            playerController.selectSubtitleTrack(
                id: track.id,
                styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
            )
            appliedPreferredSubtitle = true
        }
    }

    private func skipMarker(to marker: SkipSegment) {
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

    private func showAutomaticSkipFeedback(for marker: SkipSegment) {
        showFeedbackMessage(marker.isIntro
            ? String(localized: "player.skip.intro.automaticConfirmation")
            : String(localized: "player.skip.credits.automaticConfirmation"))
    }

    private func showFeedbackMessage(_ message: String, duration: TimeInterval = 2.5) {
        automaticSkipFeedbackWorkItem?.cancel()

        withAnimation(.easeInOut(duration: 0.2)) {
            automaticSkipFeedbackMessage = message
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                automaticSkipFeedbackMessage = nil
            }
        }
        automaticSkipFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func skipOverlay(marker: SkipSegment, title: String) -> some View {
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
            guard !controlsVisible,
                  !isShowingInfoPanel,
                  !nextEpisodePresentation.isPresented,
                  !sleepTimer.isPromptPresented
            else { return }
            focusedPlayerSurface = target
        }
    }

    private func seekFeedbackOverlay(_ feedback: SeekFeedback) -> some View {
        VStack {
            Spacer()
            SeekFeedbackView(feedback: feedback)
            Spacer()
        }
        .padding(.bottom, 120)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard !nextEpisodePresentation.isPresented, !dismissPauseScreen() else { return }

        switch direction {
        case .up:
            showControls(temporarily: true)
        case .left:
            guard !controlsVisible else { return }
            quickSeek(by: -seekBackwardInterval)
        case .right:
            guard !controlsVisible else { return }
            quickSeek(by: seekForwardInterval)
        case .down:
            guard !controlsVisible else { return }
            showInfoPanel()
        default:
            break
        }
    }

    private func handleSkipOverlayMoveCommand(_ direction: MoveCommandDirection) {
        handleMoveCommand(direction)

        guard !controlsVisible, !isShowingInfoPanel, viewModel.activeSkipMarker != nil else { return }

        DispatchQueue.main.async {
            guard !controlsVisible, !isShowingInfoPanel, viewModel.activeSkipMarker != nil else { return }
            focusedPlayerSurface = .skipOverlay
        }
    }

    private func showSeekFeedback(_ feedback: SeekFeedback) {
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
        let stopsForSleepTimer = sleepTimer.consumePlaybackEnd()
        guard let media = viewModel.media else {
            dismissPlayer()
            return
        }

        switch media.type {
        case .movie:
            Task {
                await handleMovieCompletion(stopsForSleepTimer: stopsForSleepTimer)
            }
        case .episode:
            Task {
                await handleEpisodeCompletion(for: media, stopsForSleepTimer: stopsForSleepTimer)
            }
        default:
            if !stopsForSleepTimer {
                dismissPlayer()
            }
        }
    }

    private func handleEpisodeCompletion(for _: MediaItem, stopsForSleepTimer: Bool) async {
        await viewModel.markPlaybackFinished()

        guard viewModel.usesCommonPlaybackQueue else {
            if !stopsForSleepTimer {
                await MainActor.run { dismissPlayer() }
            }
            return
        }

        guard let nextViewModel = viewModel.makeNextPlayerViewModel() else {
            if !stopsForSleepTimer {
                await MainActor.run { dismissPlayer() }
            }
            return
        }

        if sharePlayCoordinator.isInSession, let next = nextViewModel.media {
            await MainActor.run { sharePlayCoordinator.updateToNextItem(next) }
            return
        }

        // The sleep timer asked to stop here: offer the next episode without counting down to it.
        let autoplay = stopsForSleepTimer ? .disabled : settingsManager.playback.nextEpisodeAutoplay
        if autoplay == .immediately {
            await startPlayback(using: nextViewModel)
        } else {
            nextEpisodePresentation.present(next: nextViewModel, mode: autoplay)
        }
    }

    private func handleMovieCompletion(stopsForSleepTimer: Bool) async {
        await viewModel.markPlaybackFinished()
        guard !stopsForSleepTimer else { return }

        if viewModel.usesCommonPlaybackQueue {
            guard let nextViewModel = viewModel.makeNextPlayerViewModel() else {
                await MainActor.run { dismissPlayer() }
                return
            }
            if sharePlayCoordinator.isInSession, let next = nextViewModel.media {
                await MainActor.run { sharePlayCoordinator.updateToNextItem(next) }
                return
            }
            await startPlayback(using: nextViewModel)
            return
        }

        await MainActor.run { dismissPlayer() }
    }

    private func startPlayback(using nextViewModel: PlayerViewModel) async {
        await MainActor.run {
            activePlaybackURL = nil
            viewModel = nextViewModel
        }
        await viewModel.load()
    }

    private func startPlayback(for activity: StrimrWatchActivity) async {
        do {
            let nextViewModel = try await sharePlayCoordinator.playerViewModel(for: activity)
            await startPlayback(using: nextViewModel)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            sharePlayCoordinator.errorMessage = String(localized: "sharePlay.error.mediaUnavailable")
        }
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
        } catch let error as MediaServerAccessRecoveryError {
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
        pendingRecoveryAudioProviderStreamID = audioTracks.first {
            $0.id == selectedAudioTrackID
        }?.providerStreamID
        pendingRecoverySubtitleProviderStreamID = subtitleTracks.first {
            $0.id == selectedSubtitleTrackID
        }?.providerStreamID
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
        } catch let error as MediaServerAccessRecoveryError {
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
        } catch let error as MediaServerAccessRecoveryError {
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
        if let error, let server = viewModel.serverIdentity {
            sessionManager.handleTerminalServerAccessFailure(error, server: server)
        }
        dismissPlayer(force: true)
    }

    private func presentServerRecoveryError(_ error: MediaServerAccessRecoveryError) {
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
    case settings
    case quality
    case version
    case sleepTimer
    case subtitleSearch

    var id: String {
        rawValue
    }

    var parent: PlayerSettingsSheet? {
        switch self {
        case .quality, .version, .sleepTimer:
            .settings
        case .audio, .subtitle, .speed, .settings, .subtitleSearch:
            nil
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .audio:
            "player.settings.audio"
        case .subtitle:
            "player.settings.subtitles"
        case .speed:
            "player.settings.speed"
        case .settings:
            "settings.title"
        case .quality:
            "player.settings.quality"
        case .version:
            "player.settings.version"
        case .sleepTimer:
            "player.sleepTimer.title"
        case .subtitleSearch:
            "subtitles.search.title"
        }
    }
}

private enum PlayerFocusTarget: Hashable {
    case controlsProxy
    case skipOverlay
}
