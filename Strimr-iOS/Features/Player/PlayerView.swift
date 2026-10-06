import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @State var viewModel: PlayerViewModel
    @State private var playerController = PlayerController()
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var automaticSkipFeedbackWorkItem: DispatchWorkItem?
    @State private var automaticSkipFeedbackMessage: String?
    @State private var isScrubbing = false
    @State private var videoFormatBadge: PlayerVideoFormatBadge?
    @State private var sheetPresentation = IsolatedSheetPresentation<PlayerSheet>()
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
    @State private var showingTerminationAlert = false
    @State private var terminationAlertMessage = ""
    @State private var subtitleSearchErrorMessage = ""
    @State private var showingSubtitleSearchError = false
    @State private var isRotationLocked = false
    @State private var isShowingSharePlayExitPrompt = false
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
    @State private var qualityNoticeMessage: String?
    @State private var offlineHandoff: LocalPlaybackRequest?
    @State private var isShowingOfflineInterruption = false
    @State private var activeOffsetBar: PlaybackOffsetKind?

    private let controlsHideDelay: TimeInterval = 3.0
    private var seekBackwardInterval: Double {
        Double(settingsManager.playback.seekBackwardSeconds)
    }

    private var seekForwardInterval: Double {
        Double(settingsManager.playback.seekForwardSeconds)
    }

    init(viewModel: PlayerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        configuredPlayerView
    }

    private var configuredPlayerView: some View {
        let base = AnyView(
            playerScene
                .statusBarHidden()
                .overlay {
                    playerOverlay
                }
                .overlay(alignment: .bottom) {
                    infoPanelOverlay
                },
        )

        let lifecycle = AnyView(
            base
                .onAppear {
                    playerController.onMediaLoaded = handleMediaLoaded
                    playerController.onPlaybackEnded = handlePlaybackEnded
                    playerController.onPictureInPictureStartFailed = {
                        guard scenePhase == .background else { return }
                        preparePlaybackForBackground()
                    }
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
                    nextEpisodePresentation.cancel()
                    sleepTimer.cancel()
                    viewModel.handleStop()
                    playerController.onPictureInPictureStartFailed = nil
                    hideControlsWorkItem?.cancel()
                    automaticSkipFeedbackWorkItem?.cancel()
                    playerController.stop()
                    AppDelegate.orientationLock = .all
                    isRotationLocked = false
                    if sharePlayCoordinator.isInSession {
                        sharePlayCoordinator.leave()
                    }
                    sharePlayCoordinator.detachPlayer(playerController)
                }
                .task {
                    await viewModel.load(quality: settingsManager.playback.qualityPreset)
                },
        )

        let playbackObservers = AnyView(
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
                }
                .onChange(of: playerController.errorMessage) { _, newValue in
                    guard let newValue else { return }
                    Task { await handlePlaybackError(newValue) }
                }
                .onChange(of: viewModel.position) { _, newValue in
                    guard !isScrubbing else { return }
                    timelinePosition = newValue
                }
                .onChange(of: timelinePosition) { _, newValue in
                    guard isScrubbing else { return }
                    playerController.updateScrubPreview(to: newValue)
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
                }
                .onChange(of: isStreamingServerUnreachable) { _, isUnreachable in
                    guard isUnreachable else { return }
                    handleStreamingServerLost()
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
                }
                .onChange(of: sleepTimer.isPromptPresented) { _, isPresented in
                    if isPresented {
                        sheetPresentation.item = nil
                        hideInfoPanel()
                        hideControls()
                    }
                }
                .onChange(of: nextEpisodePresentation.isPresented) { _, isPresented in
                    guard isPresented else { return }
                    withAnimation(.easeInOut) {
                        isShowingInfoPanel = false
                    }
                },
        )

        return sessionObservers
            .overlay {
                IsolatedSheetPresentationHost(
                    presentation: sheetPresentation,
                    refreshID: PlayerSheetRefreshID(
                        settingsAudioTracks: settingsAudioTracks,
                        settingsSubtitleTracks: settingsSubtitleTracks,
                        selectedAudioTrackID: selectedAudioTrackID,
                        selectedSubtitleTrackID: selectedSubtitleTrackID,
                        playbackRate: playbackRate,
                        syncItems: playerController.offsetMenuItems(burnsSubtitles: viewModel.burnsSubtitles),
                    ),
                    onDismiss: { showControls(temporarily: true) },
                ) { sheet in
                    switch sheet {
                    case .settings:
                        playbackSettingsSheet
                            .presentationDetents([.medium])
                    case .subtitleSearch:
                        subtitleSearchSheet
                    }
                }
                .equatable()
            }
            .alert("player.termination.title", isPresented: $showingTerminationAlert) {
                Button("player.termination.dismiss") {
                    dismissPlayer(force: true)
                }
            } message: {
                Text(terminationAlertMessage)
            }
            .alert("offline.player.interrupted.title", isPresented: $isShowingOfflineInterruption) {
                if let offlineHandoff {
                    Button("offline.player.resumeDownloaded") {
                        self.offlineHandoff = nil
                        Task { await startPlayback(using: PlayerViewModel(request: offlineHandoff)) }
                    }
                }
                Button("player.termination.dismiss", role: .cancel) {
                    offlineHandoff = nil
                    dismissPlayer(force: true)
                }
            } message: {
                Text(offlineHandoff == nil
                    ? "offline.player.interrupted.message"
                    : "offline.player.interrupted.downloadedMessage")
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
            .confirmationDialog("sharePlay.leave.title", isPresented: $isShowingSharePlayExitPrompt) {
                Button("sharePlay.leave.action", role: .destructive) {
                    sharePlayCoordinator.leave()
                    dismissPlayer(force: true)
                }

                Button("common.actions.cancel", role: .cancel) {}
            } message: {
                Text("sharePlay.leave.message")
            }
    }

    private var playerScene: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerSurfaceView(controller: playerController)
                .onAppear {
                    showControls(temporarily: true)
                }
                .ignoresSafeArea()

            SubtitleOverlayView(
                cues: playerController.subtitleCues,
                currentTime: playerController.subtitlePosition,
                maxCueDuration: playerController.subtitleMaxCueDuration,
                appearance: settingsManager.playback.subtitleAppearance,
                bottomPadding: controlsVisible ? 120 : 48,
                videoSize: playerController.sourceVideoSize,
                assRenderer: playerController.assRenderer,
                assReloadSignal: playerController.assReloadSignal,
                activeSubtitleCodec: playerController.activeSubtitleCodec,
            )
            .ignoresSafeArea()
        }
    }

    private var playerOverlay: some View {
        let activeMarker = viewModel.activeSkipMarker
        let skipTitle = skipTitle(for: activeMarker)

        return ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    if isShowingInfoPanel {
                        hideInfoPanel()
                    } else {
                        controlsVisible ? hideControls() : showControls(temporarily: true)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 24).onEnded { value in
                        let translation = value.translation
                        if translation.height < -60, abs(translation.height) > abs(translation.width) {
                            showInfoPanel()
                        }
                    },
                )

            if viewModel.isBuffering || isRecoveringServerAccess {
                bufferingOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            if controlsVisible, !isShowingInfoPanel {
                PlayerControlsView(
                    media: viewModel.media,
                    isPaused: viewModel.isPaused,
                    isBuffering: viewModel.isBuffering,
                    videoResolution: viewModel.media?.playbackResolutionLabel,
                    videoFormatBadge: videoFormatBadge,
                    position: timelineBinding,
                    duration: viewModel.duration,
                    bufferedAhead: viewModel.bufferedAhead,
                    bufferBasePosition: viewModel.position,
                    playbackRate: playbackRate,
                    showsEndsAtTime: settingsManager.playback.showEndsAtTime,
                    isScrubbing: isScrubbing,
                    onDismiss: { dismissPlayer() },
                    onShowSettings: showSettings,
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
                    isRotationLocked: isRotationLocked,
                    onToggleRotationLock: toggleRotationLock,
                    isSharePlay: sharePlayCoordinator.isInSession,
                    showsPictureInPicture: playerController.showsPictureInPictureControl,
                    isPictureInPictureEnabled: playerController.isPictureInPictureAvailable
                        && !playerController.isPictureInPictureActive
                        && !playerController.isPictureInPictureTransitioning,
                    onStartPictureInPicture: playerController.startPictureInPicture,
                    hasInfoPanel: canShowInfoPanel,
                    onShowInfoPanel: showInfoPanel,
                    isLive: viewModel.isLivePlayback,
                    behindLiveSeconds: playerController.behindLiveSeconds,
                    onGoLive: playerController.seekToLiveEdge,
                    canSwitchPreviousChannel: viewModel.canSwitchToPreviousLiveChannel,
                    canSwitchNextChannel: viewModel.canSwitchToNextLiveChannel,
                    onPreviousChannel: { switchLiveChannel(by: -1) },
                    onNextChannel: { switchLiveChannel(by: 1) },
                    showsSettingsIndicator: playerController.subtitleDelayMilliseconds != 0,
                    sleepTimer: sleepTimer,
                )
                .transition(.opacity)
            }

            if let activeOffsetBar, !isShowingInfoPanel {
                offsetBar(activeOffsetBar)
            }

            if !controlsVisible, let activeMarker, let skipTitle {
                skipOverlay(marker: activeMarker, title: skipTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }

            if let automaticSkipFeedbackMessage {
                AutomaticSkipFeedbackView(message: automaticSkipFeedbackMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, controlsVisible ? 150 : 32)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(false)
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
    }

    private func offsetBar(_ kind: PlaybackOffsetKind) -> some View {
        let alignment = PlayerOffsetBar.alignment(for: settingsManager.playback.subtitleVerticalPosition)
        let edge: Edge.Set = alignment == .top ? .top : .bottom
        // Clears the header (top) or the transport controls (bottom) while they are shown.
        let inset: CGFloat = controlsVisible ? (alignment == .top ? 64 : 190) : 12
        return PlayerOffsetBar(
            controller: playerController,
            kind: kind,
            burnsSubtitles: viewModel.burnsSubtitles,
            onDone: closeOffsetBar,
        )
        .padding(.horizontal, 16)
        .padding(edge, inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .transition(.opacity)
    }

    @ViewBuilder
    private var infoPanelOverlay: some View {
        if isShowingInfoPanel, let media = viewModel.media {
            GeometryReader { proxy in
                PlayerInfoPanelView(
                    media: media,
                    services: viewModel.artworkServices,
                    queueItems: viewModel.queueItems,
                    queueCurrentIndex: viewModel.queueCurrentIndex ?? 0,
                    showsQueue: viewModel.hasNavigableQueue && viewModel.artworkServices != nil,
                    chapters: viewModel.chapters,
                    currentPosition: viewModel.position,
                    selectedTab: $infoPanelTab,
                    onSelectQueueItem: selectQueueItem(at:),
                    onSelectChapter: selectChapter(_:),
                    onClose: hideInfoPanel,
                )
                // Keeps at least the upper part of the video visible.
                .frame(maxHeight: proxy.size.height * 0.6)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var bufferingOverlay: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)

            Text("player.status.buffering")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.bottom, 20)
    }

    private var playbackSettingsSheet: some View {
        PlaybackSettingsView(
            audioTracks: settingsAudioTracks,
            subtitleTracks: settingsSubtitleTracks,
            selectedAudioTrackID: selectedAudioTrackID,
            selectedSubtitleTrackID: selectedSubtitleTrackID,
            playbackRate: playbackRate,
            quality: viewModel.selectedQuality,
            showsQualitySelection: !viewModel.isLocalPlayback,
            versions: viewModel.versionOptions,
            onSelectVersion: { selectVersion($0) },
            onSelectAudio: selectAudioTrack(_:),
            onSelectSubtitle: selectSubtitleTrack(_:),
            onSearchSubtitles: viewModel.canSearchSubtitles
                ? { sheetPresentation.item = .subtitleSearch }
                : nil,
            onResetTrackSelections: viewModel.canResetRememberedTrackSelections
                ? { viewModel.resetRememberedTrackSelections() }
                : nil,
            onSelectPlaybackRate: selectPlaybackRate(_:),
            onSelectQuality: { selectQuality($0) },
            syncItems: playerController.offsetMenuItems(burnsSubtitles: viewModel.burnsSubtitles),
            onSelectSync: openOffsetBar(_:),
            sleepTimer: sleepTimer,
            sleepTimerModes: SleepTimerMode.available(
                isLive: viewModel.isLivePlayback,
                hasChapters: viewModel.hasNavigableChapters,
            ),
            sleepTimerMediaKind: viewModel.media?.type,
            isSleepTimerAvailable: !sharePlayCoordinator.isInSession,
            onSelectSleepTimer: selectSleepTimer(_:),
            onClose: { sheetPresentation.item = nil },
        )
        .presentationBackground(.ultraThinMaterial)
    }

    @ViewBuilder
    private var subtitleSearchSheet: some View {
        if let services = viewModel.subtitleSearchServices {
            SubtitleSearchView(
                itemID: viewModel.currentRatingKey,
                titlePlaceholder: viewModel.subtitleSearchTitlePlaceholder,
                services: services,
                onAttached: handleAttachedSubtitle(_:),
            )
        }
    }

    private var canShowInfoPanel: Bool {
        viewModel.media != nil && !viewModel.isLivePlayback
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
        playerController.togglePlayback()
        showControls(temporarily: true)
    }

    private func showSettings() {
        refreshTracks()
        sheetPresentation.item = .settings
        hideControlsWorkItem?.cancel()
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
        showControls(temporarily: true)
    }

    private func showInfoPanel() {
        guard canShowInfoPanel, !isShowingInfoPanel else { return }
        hideControlsWorkItem?.cancel()
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
        showControls(temporarily: true)
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

    private func selectChapter(_ chapter: MediaChapter) {
        playerController.seek(to: chapter.startTime)
        viewModel.position = chapter.startTime
        timelinePosition = chapter.startTime
        hideInfoPanel()
    }

    private func toggleRotationLock() {
        if isRotationLocked {
            AppDelegate.orientationLock = .all
            isRotationLocked = false
        } else {
            AppDelegate.lockToCurrentOrientation()
            isRotationLocked = true
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
        sheetPresentation.item = nil
        showFeedbackMessage(
            String(localized: "player.sleepTimer.confirmation \(mode.title(for: viewModel.media?.type))"),
        )
    }

    private func selectQuality(_ quality: TranscodeQualityPreset, force: Bool = false) {
        guard force || quality != viewModel.selectedQuality else { return }
        let position = max(playerController.position, viewModel.position)
        let wasPaused = playerController.isPaused
        sheetPresentation.item = nil
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
        sheetPresentation.item = nil
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

    private func dismissPlayer(force: Bool = false) {
        hideControlsWorkItem?.cancel()
        if sharePlayCoordinator.isInSession, !force {
            isShowingSharePlayExitPrompt = true
        } else {
            dismiss()
        }
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
        guard !playerController.isPictureInPictureActive,
              !playerController.isPictureInPictureTransitioning
        else { return }

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
        withAnimation(.easeInOut) {
            controlsVisible = true
        }

        if temporarily, !isScrubbing {
            scheduleControlsHide()
        } else {
            hideControlsWorkItem?.cancel()
        }
    }

    private func hideControls() {
        hideControlsWorkItem?.cancel()
        withAnimation(.easeInOut) {
            controlsVisible = false
        }
    }

    private func scheduleControlsHide() {
        hideControlsWorkItem?.cancel()
        guard activeOffsetBar == nil else { return }

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
        SkipMarkerButton(title: title) {
            skipMarker(to: marker)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    private func handlePlaybackEnded() {
        let stopsForSleepTimer = sleepTimer.consumePlaybackEnd()
        guard let media = viewModel.media else {
            dismissPlayer(force: true)
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
                dismissPlayer(force: true)
            }
        }
    }

    private func handleEpisodeCompletion(for _: MediaItem, stopsForSleepTimer: Bool) async {
        await viewModel.markPlaybackFinished()

        guard viewModel.usesCommonPlaybackQueue else {
            if !stopsForSleepTimer {
                await MainActor.run { dismissPlayer(force: true) }
            }
            return
        }

        guard let nextViewModel = viewModel.makeNextPlayerViewModel() else {
            if !stopsForSleepTimer {
                await MainActor.run { dismissPlayer(force: true) }
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
                await MainActor.run { dismissPlayer(force: true) }
                return
            }
            if sharePlayCoordinator.isInSession, let next = nextViewModel.media {
                await MainActor.run { sharePlayCoordinator.updateToNextItem(next) }
                return
            }
            await startPlayback(using: nextViewModel)
            return
        }

        await MainActor.run { dismissPlayer(force: true) }
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

    /// The stream is considered lost when there is no network at all, or when its server is unreachable and the
    /// player stalls; a single failed side request must not interrupt a stream that still plays.
    private var isStreamingServerUnreachable: Bool {
        guard let server = viewModel.streamingServer, offlineCoordinator.isUnreachable(server) else { return false }
        return !offlineCoordinator.availability.hasNetworkPath || playerController.isBuffering
    }

    /// Streaming cannot continue without its server: stop cleanly and offer the downloaded copy when there is one.
    private func handleStreamingServerLost() {
        guard !sharePlayCoordinator.isInSession else { return }
        playerController.pause()
        offlineHandoff = viewModel.prepareOfflineHandoff()
        viewModel.handleStop()
        isShowingOfflineInterruption = true
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

private struct PlayerSheetRefreshID: Hashable {
    let settingsAudioTracks: [PlaybackSettingsTrack]
    let settingsSubtitleTracks: [PlaybackSettingsTrack]
    let selectedAudioTrackID: Int?
    let selectedSubtitleTrackID: Int?
    let playbackRate: Float
    let syncItems: [PlaybackOffsetMenuItem]
}

private enum PlayerSheet: String, Identifiable {
    case settings
    case subtitleSearch

    var id: String {
        rawValue
    }
}
