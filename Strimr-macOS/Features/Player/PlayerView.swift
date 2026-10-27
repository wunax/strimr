import AppKit
import SwiftUI

struct PlayerWindowView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let presentation = appModel.playerPresentation,
           let viewModel = playerViewModel(for: presentation)
        {
            PlayerView(
                viewModel: viewModel,
                presentationID: presentation.id,
            )
            .environment(presentation.mediaServices)
            .id(presentation.id)
        } else {
            ContentUnavailableView("player.window.title", systemImage: "play.rectangle")
        }
    }

    private func playerViewModel(
        for presentation: AppModel.PlayerPresentation,
    ) -> PlayerViewModel? {
        if let media = presentation.localMedia, let url = presentation.localPlaybackURL {
            return PlayerViewModel(
                localMedia: media,
                localPlaybackURL: url,
                localExternalSubtitles: presentation.localExternalSubtitles,
                owner: presentation.localOwner,
                resumes: presentation.shouldResumeFromOffset,
            )
        }
        if let queue = presentation.mediaQueue, let services = presentation.mediaServices {
            return PlayerViewModel(
                queue: queue,
                services: services,
                shouldResumeFromOffset: presentation.shouldResumeFromOffset,
                launchNotice: presentation.notice,
            )
        }
        if let context = presentation.liveTVContext, let services = presentation.mediaServices {
            return PlayerViewModel(live: context, services: services)
        }
        return nil
    }
}

struct PlayerView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var appModel
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled

    @State private var viewModel: PlayerViewModel
    @State private var playerController = PlayerController()
    @State private var fullscreenCoordinator = PlayerFullscreenCoordinator()
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var automaticSkipFeedbackWorkItem: DispatchWorkItem?
    @State private var automaticSkipFeedbackMessage: String?
    @State private var seekFeedback: SeekFeedback?
    @State private var seekFeedbackWorkItem: DispatchWorkItem?
    @State private var isPointerInsidePlayer = false
    @State private var isScrubbing = false
    @State private var scrubPosition = 0.0
    @State private var audioTracks: [PlayerTrack] = []
    @State private var subtitleTracks: [PlayerTrack] = []
    @State private var selectedAudioTrackID: Int?
    @State private var selectedSubtitleTrackID: Int?
    @State private var pendingRecoveryAudioProviderStreamID: Int?
    @State private var pendingRecoverySubtitleProviderStreamID: Int?
    @State private var shouldRestoreTracksAfterLoad = false
    @State private var playbackRate: Float = 1
    @State private var loadedURL: URL?
    @State private var isShowingError = false
    @State private var errorMessage = ""
    @State private var sheetPresentation = IsolatedSheetPresentation<PlayerSheet>()
    @State private var subtitleSearchErrorMessage = ""
    @State private var isShowingSubtitleSearchError = false
    @State private var isShowingSharePlayExitPrompt = false
    @State private var participatesInSharePlay = false
    @State private var isShowingChapterPopover = false
    @State private var isShowingInfoPopover = false
    @State private var isShowingPlayQueue = false
    @State private var isRecoveringServerAccess = false
    @State private var isShowingServerRecoveryAlert = false
    @State private var serverRecoveryError: MediaServerAccessRecoveryError?
    @State private var lastReloadedServerAccessGeneration = -1
    @State private var shouldResumeAfterMediaLoad = false
    @State private var shouldPauseAfterMediaLoad = false
    @State private var nextEpisodePresentation = NextEpisodePresentation()
    @State private var sleepTimer = SleepTimer()
    @State private var pauseScreen = PauseScreenPresentation()
    @State private var lastPointerLocation: CGPoint?
    @State private var qualityNoticeMessage: String?
    @State private var offlineHandoff: LocalPlaybackRequest?
    @State private var isShowingOfflineInterruption = false
    @State private var activeOffsetBar: PlaybackOffsetKind?

    private let presentationID: UUID
    private let controlsHideDelay: TimeInterval = 3
    private let seekFeedbackDelay: TimeInterval = 1.2

    init(viewModel: PlayerViewModel, presentationID: UUID) {
        _viewModel = State(initialValue: viewModel)
        self.presentationID = presentationID
    }

    var body: some View {
        configuredPlayerView
    }

    private var playerScene: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerSurfaceView(controller: playerController)
                .ignoresSafeArea()

            SubtitleOverlayView(
                cues: playerController.subtitleCues,
                currentTime: playerController.subtitlePosition,
                maxCueDuration: playerController.subtitleMaxCueDuration,
                appearance: settingsManager.playback.subtitleAppearance,
                bottomPadding: controlsVisible ? 96 : 48,
                videoSize: playerController.sourceVideoSize,
                assRenderer: playerController.assRenderer,
                activeSubtitleCodec: playerController.activeSubtitleCodec,
            )
            .ignoresSafeArea()
            .opacity(pauseScreen.isPresented ? 0 : 1)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2)
                        .exclusively(
                            before: TapGesture()
                                .onEnded { toggleControlsVisibility() },
                        ),
                )

            if viewModel.isLoading || viewModel.isBuffering || isRecoveringServerAccess {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if controlsVisible, !isShowingPlayQueue, !nextEpisodePresentation.isPresented,
               !sleepTimer.isPromptPresented
            {
                controls
                    .transition(.opacity)
            }

            if let activeOffsetBar, !isShowingPlayQueue {
                offsetBar(activeOffsetBar)
            }

            if isShowingPlayQueue,
               let services = viewModel.artworkServices
            {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: hidePlayQueue)

                PlayerQueueView(
                    items: viewModel.queueItems,
                    currentIndex: viewModel.queueCurrentIndex ?? 0,
                    services: services,
                    layout: .drawer,
                    onSelect: selectQueueItem(at:),
                    onClose: hidePlayQueue,
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if let automaticSkipFeedbackMessage {
                AutomaticSkipFeedbackView(message: automaticSkipFeedbackMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, controlsVisible ? 110 : 32)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(false)
            }

            if let seekFeedback {
                VStack {
                    Spacer()
                    SeekFeedbackView(feedback: seekFeedback)
                    Spacer()
                }
                .padding(.bottom, 80)
                .allowsHitTesting(false)
            }

            if pauseScreen.isPresented, let media = viewModel.media {
                PauseScreenOverlay(
                    media: media,
                    position: playerController.position,
                    duration: playerController.duration ?? viewModel.duration,
                    playbackRate: playbackRate,
                    showsEndsAtTime: settingsManager.playback.showEndsAtTime,
                    isLive: viewModel.isLivePlayback,
                )
                .transition(.opacity)
            }

            keyboardCommands

            if nextEpisodePresentation.isPresented,
               let services = viewModel.artworkServices
            {
                NextEpisodeOverlay(
                    presentation: nextEpisodePresentation,
                    services: services,
                    onPlay: { nextViewModel in
                        await startPlayback(using: nextViewModel)
                    },
                    onClose: { closePlayer(force: true) },
                )
            }

            if sleepTimer.isPromptPresented {
                SleepTimerPromptOverlay(sleepTimer: sleepTimer)
            }
        }
        .animation(Motion.animation(Motion.controls, reduceMotion: reduceMotion), value: pauseScreen.isPresented)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { toggleFullScreen() },
        )
        .background(.black)
        .background {
            PlayerWindowReader { window in
                fullscreenCoordinator.attach(to: window)
            }
        }
    }

    private var configuredPlayerView: some View {
        let lifecycle = AnyView(
            playerScene
                .onContinuousHover { phase in
                    handlePointerMovement(phase)
                }
                .task {
                    configureController()
                    if sharePlayCoordinator.isInSession {
                        participatesInSharePlay = true
                        sharePlayCoordinator.attachPlayer(
                            playerController,
                            ratingKey: viewModel.currentRatingKey,
                        )
                    }
                    await viewModel.load(quality: settingsManager.playback.qualityPreset)
                    startPlaybackIfNeeded(viewModel.playbackURL)
                }
                .onDisappear {
                    nextEpisodePresentation.cancel()
                    sleepTimer.cancel()
                    pauseScreen.cancel()
                    hideControlsWorkItem?.cancel()
                    automaticSkipFeedbackWorkItem?.cancel()
                    seekFeedbackWorkItem?.cancel()
                    fullscreenCoordinator.detach()
                    restoreCursor()
                    stopPlayback()
                    appModel.resetPlayer(ifPresenting: presentationID)
                    if participatesInSharePlay, sharePlayCoordinator.isInSession {
                        sharePlayCoordinator.leave()
                    }
                    sharePlayCoordinator.detachPlayer(playerController)
                    participatesInSharePlay = false
                },
        )

        let playbackObservers = AnyView(
            lifecycle
                .onChange(of: viewModel.playbackURL) { _, url in
                    startPlaybackIfNeeded(url)
                }
                .onChange(of: playerController.isPaused) { _, isPaused in
                    viewModel.handlePlaybackState(isPaused: isPaused, isBuffering: playerController.isBuffering)
                    sleepTimer.handlePlaybackStateChange(isPaused: isPaused)
                    if isPaused {
                        showControls(temporarily: false)
                    } else {
                        showControls(temporarily: true)
                    }
                }
                .onChange(of: playerController.isBuffering) { _, isBuffering in
                    viewModel.handlePlaybackState(isPaused: playerController.isPaused, isBuffering: isBuffering)
                }
                .onChange(of: playerController.position) { _, position in
                    viewModel.handlePlaybackPosition(position, isScrubbing: isScrubbing)
                    if !isScrubbing {
                        scrubPosition = viewModel.position
                    }
                    handleAutomaticMarkerSkipIfNeeded()
                    sleepTimer.handlePosition(
                        position,
                        duration: playerController.duration ?? viewModel.duration,
                        chapters: viewModel.chapters,
                    )
                }
                .onChange(of: scrubPosition) { _, position in
                    guard isScrubbing else { return }
                    playerController.updateScrubPreview(to: position)
                }
                .onChange(of: playerController.duration) { _, duration in
                    viewModel.handlePlaybackDuration(duration)
                }
                .onChange(of: playerController.bufferedAhead) { _, bufferedAhead in
                    viewModel.handleBufferedAhead(bufferedAhead)
                },
        )

        let presentationObservers = AnyView(
            playbackObservers
                .onChange(of: playerController.errorMessage) { _, error in
                    guard let error else { return }
                    Task { await handlePlaybackError(error) }
                }
                .onChange(of: viewModel.terminationMessage) { _, error in
                    guard let error else { return }
                    showError(error)
                }
                .onChange(of: viewModel.hasNavigableChapters) { _, hasChapters in
                    if !hasChapters {
                        isShowingChapterPopover = false
                    }
                }
                .onChange(of: isShowingChapterPopover) { _, isShowing in
                    if isShowing {
                        hideControlsWorkItem?.cancel()
                    } else {
                        showControls(temporarily: true)
                    }
                }
                .onChange(of: isShowingInfoPopover) { _, isShowing in
                    if isShowing {
                        hideControlsWorkItem?.cancel()
                    } else {
                        showControls(temporarily: true)
                    }
                }
                .onChange(of: isShowingPlayQueue) { _, isShowing in
                    if isShowing {
                        hideControlsWorkItem?.cancel()
                        restoreCursor()
                    } else {
                        showControls(temporarily: true)
                    }
                }
                .onChange(of: sharePlayCoordinator.activityChangeID) { _, _ in
                    guard participatesInSharePlay,
                          let activity = sharePlayCoordinator.activity,
                          activity.ratingKey != viewModel.currentRatingKey
                    else { return }
                    Task { await startPlayback(for: activity) }
                }
                .onChange(of: viewModel.serverAccessGeneration) { _, generation in
                    Task { await reloadPlaybackAfterServerAccessChange(generation) }
                }
                .onChange(of: viewModel.serverAccessRecoveryError) { _, error in
                    guard let error else { return }
                    presentServerRecoveryError(error)
                }
                .onChange(of: fullscreenCoordinator.isFullScreen) { wasFullScreen, isFullScreen in
                    if wasFullScreen, !isFullScreen {
                        showControls(temporarily: true)
                    }
                }
                .onChange(of: isStreamingServerUnreachable) { _, isUnreachable in
                    guard isUnreachable else { return }
                    handleStreamingServerLost()
                }
                .onChange(of: isSharePlayPlayback) { _, isSharePlay in
                    if isSharePlay {
                        sleepTimer.cancel()
                    }
                }
                .onChange(of: isPauseScreenEligible, initial: true) { _, isEligible in
                    pauseScreen.update(isEligible: isEligible)
                }
                .onChange(of: pauseScreen.isPresented) { _, isPresented in
                    if isPresented {
                        hideControls(force: true)
                    }
                },
        )

        return presentationObservers
            .overlay {
                IsolatedSheetPresentationHost(
                    presentation: sheetPresentation,
                    refreshID: presentationID,
                ) { sheet in
                    switch sheet {
                    case .subtitleSearch:
                        subtitleSearchSheet
                    }
                }
                .equatable()
            }
            .alert("player.termination.title", isPresented: $isShowingError) {
                Button("player.termination.dismiss") { closePlayer(force: true) }
            } message: {
                Text(errorMessage)
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
            .alert("offline.player.interrupted.title", isPresented: $isShowingOfflineInterruption) {
                if let offlineHandoff {
                    Button("offline.player.resumeDownloaded") {
                        self.offlineHandoff = nil
                        Task { await startPlayback(using: PlayerViewModel(request: offlineHandoff)) }
                    }
                }
                Button("player.termination.dismiss", role: .cancel) {
                    offlineHandoff = nil
                    closePlayer(force: true)
                }
            } message: {
                Text(offlineHandoff == nil
                    ? "offline.player.interrupted.message"
                    : "offline.player.interrupted.downloadedMessage")
            }
            .alert("subtitles.search.activation.error", isPresented: $isShowingSubtitleSearchError) {
                Button("common.actions.done", role: .cancel) {}
            } message: {
                Text(subtitleSearchErrorMessage)
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
            .alert(
                Text(viewModel.launchNotice ?? ""),
                isPresented: Binding(
                    get: { viewModel.launchNotice != nil },
                    set: {
                        if !$0 {
                            viewModel.launchNotice = nil
                        }
                    },
                ),
            ) {
                Button("common.actions.done") { viewModel.launchNotice = nil }
            }
            .confirmationDialog("sharePlay.leave.title", isPresented: $isShowingSharePlayExitPrompt) {
                Button("sharePlay.leave.action", role: .destructive) {
                    sharePlayCoordinator.leave()
                    participatesInSharePlay = false
                    closePlayer(force: true)
                }

                Button("common.actions.cancel", role: .cancel) {}
            } message: {
                Text("sharePlay.leave.message")
            }
    }

    private var controls: some View {
        VStack {
            HStack {
                if let media = viewModel.media {
                    titleButton(for: media)
                }
                Spacer()
                if let badge = playerController.videoFormatBadge {
                    PlayerBadge(badge.title)
                }
                if participatesInSharePlay, sharePlayCoordinator.isInSession {
                    PlayerBadge(String(localized: "sharePlay.badge"))
                }
                SleepTimerBadge(sleepTimer: sleepTimer, mediaKind: viewModel.media?.type)
                PlayerIconButton(
                    systemName: "xmark",
                    accessibilityLabel: String(localized: "common.actions.close"),
                    size: .small,
                ) {
                    closePlayer()
                }
            }

            Spacer()

            VStack(spacing: 14) {
                if let marker = viewModel.activeSkipMarker {
                    HStack {
                        Spacer()
                        Button {
                            playerController.seek(to: marker.endTime)
                        } label: {
                            HStack(spacing: 10) {
                                Text(marker.skipTitle)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.bold))
                            }
                        }
                        .actionButtonStyle(.primary)
                        .accessibilityLabel(marker.skipTitle)
                    }
                }

                if isScrubbing,
                   let scrubPreview = playerController.scrubPreview,
                   scrubPreview.image != nil
                {
                    PlayerScrubPreviewRail(
                        preview: scrubPreview,
                        duration: max(max(viewModel.duration ?? 0, scrubPosition), 1),
                        horizontalInset: 74,
                    )
                    .transition(.opacity)
                }

                if settingsManager.playback.showChaptersOnTimeline,
                   isScrubbing,
                   let chapter = viewModel.chapter(at: scrubPosition)
                {
                    Text(chapter.displayTitle)
                        .font(.cardMetadata.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                HStack(spacing: 10) {
                    Text(formatTime(scrubPosition))
                        .font(.cardMetadata.monospacedDigit())
                        .frame(width: 64, alignment: .trailing)
                    ZStack {
                        PlayerSegmentedTimelineRail(
                            chapters: settingsManager.playback.showChaptersOnTimeline
                                ? viewModel.chapters
                                : [],
                            duration: viewModel.duration,
                            position: scrubPosition,
                            bufferedEnd: viewModel.position + viewModel.bufferedAhead,
                            horizontalInset: 10,
                        )
                        .frame(height: 22)

                        PlayerTracklessSlider(
                            value: $scrubPosition,
                            in: 0 ... max(viewModel.duration ?? 1, 1),
                            onEditingChanged: { editing in
                                withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
                                    isScrubbing = editing
                                }
                                if editing {
                                    playerController.beginScrubPreviewing(at: scrubPosition)
                                    showControls(temporarily: false)
                                }
                                if !editing {
                                    playerController.endScrubPreviewing()
                                    playerController.seek(to: scrubPosition)
                                    viewModel.handlePlaybackPosition(scrubPosition, isScrubbing: false)
                                    showControls(temporarily: true)
                                }
                            },
                        )
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(formatTime(viewModel.duration ?? 0))
                            .frame(width: 64, alignment: .leading)

                        if settingsManager.playback.showEndsAtTime {
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                if let endsAtText = playerEndsAtText(
                                    position: scrubPosition,
                                    duration: viewModel.duration,
                                    playbackRate: playbackRate,
                                    now: context.date,
                                ) {
                                    Text(endsAtText)
                                        .font(.cardMetadata.monospacedDigit())
                                        .foregroundStyle(.textSecondary)
                                }
                            }
                        }
                    }
                    .font(.cardMetadata.monospacedDigit())
                    .fixedSize()
                }

                HStack(spacing: 14) {
                    // Equal flexible sides keep the transport centered in the window whatever each side holds.
                    leadingControls
                        .frame(maxWidth: .infinity, alignment: .leading)
                    transportControls
                    trailingControls
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // Menus and the remaining buttons (volume, chapters) take the small round control look.
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.playerControl(diameter: PlayerIconButton.Size.small.diameter))
                .font(PlayerIconButton.Size.small.font)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background {
            PlayerControlsBackground()
        }
    }

    private var leadingControls: some View {
        HStack(spacing: 14) {
            volumeControl

            if viewModel.isLivePlayback {
                Button {
                    playerController.seekToLiveEdge()
                } label: {
                    Label(
                        playerController.behindLiveSeconds < 2
                            ? String(localized: "livetv.player.live")
                            : String(localized: "livetv.player.goLive"),
                        systemImage: "dot.radiowaves.left.and.right",
                    )
                }
                .actionButtonStyle(.primary)
                .disabled(playerController.behindLiveSeconds < 2)
            }

            if viewModel.hasNavigableChapters {
                chapterButton
            }

            if viewModel.hasNavigableQueue {
                PlayerIconButton(
                    systemName: "list.bullet.rectangle",
                    accessibilityLabel: String(localized: "player.queue.open"),
                    size: .small,
                ) {
                    showPlayQueue()
                }
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 14) {
            if viewModel.isLivePlayback {
                PlayerIconButton(
                    systemName: "chevron.up",
                    accessibilityLabel: String(localized: "livetv.player.previousChannel"),
                    size: .small,
                ) {
                    switchLiveChannel(by: -1)
                }
                .disabled(!viewModel.canSwitchToPreviousLiveChannel)
            }

            PlayerIconButton(
                systemName: "gobackward.\(settingsManager.playback.seekBackwardSeconds)",
                accessibilityLabel: String(
                    localized: "player.controls.rewindSeconds \(settingsManager.playback.seekBackwardSeconds)",
                ),
            ) {
                playerController.seek(by: -seekBackwardInterval)
            }

            PlayPauseButton(isPaused: playerController.isPaused) {
                playerController.togglePlayback()
            }

            PlayerIconButton(
                systemName: "goforward.\(settingsManager.playback.seekForwardSeconds)",
                accessibilityLabel: String(
                    localized: "player.controls.skipForwardSeconds \(settingsManager.playback.seekForwardSeconds)",
                ),
            ) {
                playerController.seek(by: seekForwardInterval)
            }

            if viewModel.isLivePlayback {
                PlayerIconButton(
                    systemName: "chevron.down",
                    accessibilityLabel: String(localized: "livetv.player.nextChannel"),
                    size: .small,
                ) {
                    switchLiveChannel(by: 1)
                }
                .disabled(!viewModel.canSwitchToNextLiveChannel)
            }
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 14) {
            audioMenu
            subtitleMenu
            speedMenu
            sleepTimerMenu
            if !viewModel.isLocalPlayback, !viewModel.isLivePlayback {
                qualityMenu
            }
            if viewModel.showsVersionSelection {
                versionMenu
            }

            if playerController.showsPictureInPictureControl {
                PlayerIconButton(
                    systemName: "pip.enter",
                    accessibilityLabel: String(localized: "player.controls.pictureInPicture"),
                    size: .small,
                ) {
                    playerController.startPictureInPicture()
                }
                .disabled(
                    !playerController.isPictureInPictureAvailable
                        || playerController.isPictureInPictureActive
                        || playerController.isPictureInPictureTransitioning,
                )
            }

            PlayerIconButton(
                systemName: fullscreenCoordinator.isFullScreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: fullscreenAccessibilityLabel,
                size: .small,
            ) {
                toggleFullScreen()
            }
            .disabled(fullscreenCoordinator.isTransitioning)
        }
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
            .frame(minWidth: 560, minHeight: 640)
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Button {
                playerController.toggleMute()
                showControls(temporarily: true)
            } label: {
                Image(systemName: volumeSystemImage)
            }
            .accessibilityLabel(
                playerController.isMuted
                    ? Text("player.controls.volume.unmute")
                    : Text("player.controls.volume.mute"),
            )

            Slider(
                value: Binding(
                    get: { playerController.volume },
                    set: { playerController.setVolume($0) },
                ),
                in: 0 ... 1,
                onEditingChanged: { editing in
                    if editing {
                        showControls(temporarily: false)
                    } else {
                        showControls(temporarily: true)
                    }
                },
            )
            .frame(width: 100)
            .accessibilityLabel(Text("player.controls.volume"))
        }
    }

    private var volumeSystemImage: String {
        switch playerController.volume {
        case 0:
            "speaker.slash.fill"
        case ..<0.34:
            "speaker.wave.1.fill"
        case ..<0.67:
            "speaker.wave.2.fill"
        default:
            "speaker.wave.3.fill"
        }
    }

    private var audioMenu: some View {
        Menu {
            if audioTracks.isEmpty {
                Text("player.settings.audio.empty")
            } else {
                ForEach(audioTracks) { track in
                    menuOption(isSelected: selectedAudioTrackID == track.id) {
                        selectedAudioTrackID = track.id
                        playerController.selectAudioTrack(id: track.id)
                        Task {
                            await viewModel.persistStreamSelection(for: track)
                            if viewModel.isTranscoding {
                                selectQuality(viewModel.selectedQuality, force: true)
                            }
                        }
                    } label: {
                        Text(playerTrackTitle(track))
                    }
                }
            }
            Divider()
            offsetMenuButton(.audio)
        } label: {
            Label("player.settings.audio", systemImage: "waveform")
                .labelStyle(.iconOnly)
        }
    }

    private var subtitleMenu: some View {
        Menu {
            menuOption(isSelected: selectedSubtitleTrackID == nil) {
                if selectedSubtitleTrackID != nil {
                    playerController.setSubtitleDelay(milliseconds: 0)
                }
                selectedSubtitleTrackID = nil
                playerController.selectSubtitleTrack(
                    id: nil,
                    styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                )
                Task {
                    await viewModel.persistSubtitleStreamSelection(for: nil)
                    if viewModel.isTranscoding {
                        selectQuality(viewModel.selectedQuality, force: true)
                    }
                }
            } label: {
                Text("player.settings.subtitles.off")
            }
            ForEach(subtitleTracks) { track in
                menuOption(isSelected: selectedSubtitleTrackID == track.id) {
                    if selectedSubtitleTrackID != track.id {
                        playerController.setSubtitleDelay(milliseconds: 0)
                    }
                    selectedSubtitleTrackID = track.id
                    playerController.selectSubtitleTrack(
                        id: track.id,
                        styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                    )
                    Task {
                        await viewModel.persistSubtitleStreamSelection(for: track)
                        if viewModel.isTranscoding {
                            selectQuality(viewModel.selectedQuality, force: true)
                        }
                    }
                } label: {
                    Text(playerTrackTitle(track))
                }
            }
            if viewModel.canSearchSubtitles {
                Divider()
                Button {
                    sheetPresentation.item = .subtitleSearch
                } label: {
                    Label("subtitles.search.action", systemImage: "magnifyingglass")
                }
                .tint(.secondary)
            }
            if viewModel.canResetRememberedTrackSelections {
                Divider()
                Button {
                    viewModel.resetRememberedTrackSelections()
                } label: {
                    Label("player.settings.tracks.reset", systemImage: "arrow.counterclockwise")
                }
            }
            Divider()
            offsetMenuButton(.subtitles)
        } label: {
            Label("player.settings.subtitles", systemImage: "captions.bubble")
                .labelStyle(.iconOnly)
        }
        .overlay(alignment: .topTrailing) {
            if playerController.subtitleDelayMilliseconds != 0 {
                PlaybackOffsetIndicator()
                    .offset(x: 3, y: -3)
                    .allowsHitTesting(false)
            }
        }
    }

    private func offsetMenuButton(_ kind: PlaybackOffsetKind) -> some View {
        let item = playerController.offsetMenuItem(kind, burnsSubtitles: viewModel.burnsSubtitles)
        return Button {
            openOffsetBar(kind)
        } label: {
            Label {
                Text(item.kind.title)
                Text(item.availability.message ?? item.value)
            } icon: {
                Image(systemName: item.kind.systemImage)
            }
        }
        .disabled(!item.availability.isAvailable)
    }

    private func offsetBar(_ kind: PlaybackOffsetKind) -> some View {
        let alignment = PlayerOffsetBar.alignment(for: settingsManager.playback.subtitleVerticalPosition)
        let edge: Edge.Set = alignment == .top ? .top : .bottom
        // Clears the title row (top) or the transport controls (bottom) while they are shown.
        let inset: CGFloat = controlsVisible ? (alignment == .top ? 84 : 140) : 24
        return PlayerOffsetBar(
            controller: playerController,
            kind: kind,
            burnsSubtitles: viewModel.burnsSubtitles,
            onDone: closeOffsetBar,
        )
        .padding(.horizontal, 24)
        .padding(edge, inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .transition(.opacity)
    }

    private func openOffsetBar(_ kind: PlaybackOffsetKind) {
        hideControlsWorkItem?.cancel()
        restoreCursor()
        withAnimation(Motion.animation(Motion.panel, reduceMotion: reduceMotion)) {
            activeOffsetBar = kind
            controlsVisible = true
        }
    }

    private func closeOffsetBar() {
        playerController.commitAudioDelay()
        withAnimation(Motion.animation(Motion.panel, reduceMotion: reduceMotion)) {
            activeOffsetBar = nil
        }
        showControls(temporarily: true)
    }

    /// Uses the menu's own checkmark, which the player's label, button and color styles cannot hide.
    private func menuOption(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View,
    ) -> some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in action() }), label: label)
    }

    private func playerTrackTitle(_ track: PlayerTrack) -> String {
        PlaybackSettingsTrack(
            track: track,
            metadata: viewModel.trackMetadata(forID: track.providerStreamID),
        ).title
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlaybackSpeedOptions.all) { option in
                menuOption(isSelected: playbackRate == option.rate) {
                    playbackRate = option.rate
                    playerController.setPlaybackRate(option.rate)
                } label: {
                    Text("player.settings.speed.value \(option.valueText)")
                }
            }
        } label: {
            Label("player.settings.speed", systemImage: "speedometer")
                .labelStyle(.iconOnly)
        }
    }

    private var sleepTimerMenu: some View {
        let mediaKind = viewModel.media?.type
        return Menu {
            menuOption(isSelected: sleepTimer.mode == nil) {
                selectSleepTimer(nil)
            } label: {
                Text("player.sleepTimer.off")
            }
            ForEach(
                SleepTimerMode.available(
                    isLive: viewModel.isLivePlayback,
                    hasChapters: viewModel.hasNavigableChapters,
                ),
                id: \.self,
            ) { mode in
                menuOption(isSelected: sleepTimer.mode == mode) {
                    selectSleepTimer(mode)
                } label: {
                    Text(mode.title(for: mediaKind))
                }
            }
            if sleepTimer.deadline != nil {
                Divider()
                Button {
                    sleepTimer.extend()
                } label: {
                    Label(
                        String(localized: "player.sleepTimer.extend \(SleepTimer.extensionMinutes)"),
                        systemImage: "plus",
                    )
                }
            }
        } label: {
            Label("player.sleepTimer.title", systemImage: sleepTimer.isActive ? "moon.zzz.fill" : "moon.zzz")
                .labelStyle(.iconOnly)
        }
        .disabled(isSharePlayPlayback)
        .help(isSharePlayPlayback ? Text("player.sleepTimer.unavailableSharePlay") : Text("player.sleepTimer.title"))
    }

    private var isSharePlayPlayback: Bool {
        participatesInSharePlay && sharePlayCoordinator.isInSession
    }

    private func selectSleepTimer(_ mode: SleepTimerMode?) {
        guard let mode else {
            sleepTimer.cancel()
            return
        }
        sleepTimer.start(mode)
        showFeedbackMessage(
            String(localized: "player.sleepTimer.confirmation \(mode.title(for: viewModel.media?.type))"),
        )
    }

    private func configureSleepTimer() {
        sleepTimer.pausePlayback = {
            nextEpisodePresentation.cancelCountdown()
            playerController.pause()
        }
        sleepTimer.isPlaybackActive = {
            !playerController.isPaused && !nextEpisodePresentation.isPresented
        }
        sleepTimer.setVolumeAttenuation = { playerController.setVolumeAttenuation($0) }
        sleepTimer.onBoundaryPause = {
            showFeedbackMessage(String(localized: "player.sleepTimer.pausedFeedback"), duration: 5)
        }
    }

    private func togglePlayPauseFromKeyboard() {
        pauseScreen.registerInteraction()
        if sleepTimer.isPromptPresented {
            sleepTimer.pauseNow()
        } else {
            playerController.togglePlayback()
        }
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(TranscodeQualityPreset.displayOrder) { preset in
                menuOption(isSelected: viewModel.selectedQuality == preset) {
                    selectQuality(preset)
                } label: {
                    Text(preset.title)
                }
            }
        } label: {
            Label("player.settings.quality", systemImage: "slider.horizontal.3")
                .labelStyle(.iconOnly)
        }
    }

    private var versionMenu: some View {
        Menu {
            ForEach(viewModel.versionOptions) { version in
                menuOption(isSelected: version.isSelected) {
                    selectVersion(version.id)
                } label: {
                    Text(verbatim: version.title)
                    Text(verbatim: version.subtitle)
                }
                .disabled(!version.isAvailable)
            }
        } label: {
            Label("player.settings.version", systemImage: "film.stack")
                .labelStyle(.iconOnly)
        }
    }

    private func selectVersion(_ versionID: String) {
        guard versionID != viewModel.currentVersionID else { return }
        let position = max(playerController.position, viewModel.position)
        let wasPaused = playerController.isPaused
        Task {
            do {
                let result = try await viewModel.changeVersion(to: versionID, from: position)
                reloadPlayback(url: result.url, startPosition: result.position, wasPaused: wasPaused)
                qualityNoticeMessage = viewModel.qualityFallbackMessage
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
                qualityNoticeMessage = error.localizedDescription
            }
        }
    }

    private func selectQuality(_ quality: TranscodeQualityPreset, force: Bool = false) {
        guard force || quality != viewModel.selectedQuality else { return }
        let position = max(playerController.position, viewModel.position)
        let wasPaused = playerController.isPaused
        Task {
            do {
                let url = try await viewModel.changeQuality(to: quality, force: force)
                reloadPlayback(url: url, startPosition: position, wasPaused: wasPaused)
                qualityNoticeMessage = viewModel.qualityFallbackMessage
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
                qualityNoticeMessage = error.localizedDescription
            }
        }
    }

    private func reloadPlayback(url: URL, startPosition position: TimeInterval, wasPaused: Bool) {
        loadedURL = url
        shouldPauseAfterMediaLoad = wasPaused
        shouldResumeAfterMediaLoad = !wasPaused
        playerController.load(
            url: url,
            httpHeaders: viewModel.playbackHTTPHeaders,
            startPosition: position,
            preferredAudioTrackID: viewModel.preferredAudioStreamFFIndex,
            losslessAudio: settingsManager.playback.losslessAudio,
            spatialAudioLayout: settingsManager.playback.spatialAudioLayout,
            styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
            mediaIdentifier: viewModel.media?.id ?? url.lastPathComponent,
            providerStreamIDsByFFIndex: viewModel.providerStreamIDsByFFIndex(),
            externalSubtitles: viewModel.externalSubtitleTracks(),
            scrubThumbnailSource: viewModel.scrubThumbnailSource,
            showsScrubThumbnailPreviews: settingsManager.playback.showScrubThumbnailPreviews,
            generatesMissingScrubThumbnailPreviews:
            settingsManager.playback.generateMissingScrubThumbnailPreviews,
            showsSubtitlesOnSkipBack: settingsManager.playback.showSubtitlesOnSkipBack
                && !viewModel.isTranscoding,
            isLive: viewModel.isLivePlayback,
            nativeRemoteHLS: viewModel.liveNativeRemoteHLS,
            dvrWindowSeconds: viewModel.liveDVRWindowSeconds,
            audioDelayMilliseconds: settingsManager.playback.audioDelayMilliseconds,
            autoplay: !wasPaused,
        )
        playerController.setPlaybackRate(playbackRate)
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
            let tracks = viewModel.isTranscoding
                ? viewModel.sourcePlayerTracks()
                : playerController.trackList()
            audioTracks = tracks.filter { $0.type == .audio }
            subtitleTracks = tracks.filter { $0.type == .subtitle }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            subtitleSearchErrorMessage = error.localizedDescription
            isShowingSubtitleSearchError = true
        }
    }

    private var chapterButton: some View {
        Button {
            isShowingChapterPopover.toggle()
        } label: {
            Label("player.chapters.title", systemImage: "list.number")
                .labelStyle(.iconOnly)
        }
        .popover(isPresented: $isShowingChapterPopover, arrowEdge: .bottom) {
            PlayerChapterPopover(
                chapters: viewModel.chapters,
                currentPosition: viewModel.position,
                onSelect: selectChapter(_:),
            )
        }
    }

    private func titleButton(for media: MediaItem) -> some View {
        Button {
            toggleInfoPopover()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(media.primaryLabel).font(.sectionTitle)
                    if canShowInfo {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.textSecondary)
                    }
                }
                if let secondary = media.tertiaryLabel ?? media.secondaryLabel {
                    Text(secondary).font(.facts).foregroundStyle(.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canShowInfo)
        .help(Text("player.info.open"))
        .popover(isPresented: $isShowingInfoPopover, arrowEdge: .bottom) {
            ScrollView {
                PlayerMediaInfoView(media: media, services: viewModel.artworkServices)
                    .padding(20)
            }
            .frame(width: 460)
            .frame(maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canShowInfo: Bool {
        viewModel.media != nil && !viewModel.isLivePlayback
    }

    private func toggleInfoPopover() {
        guard canShowInfo else { return }
        if !isShowingInfoPopover {
            showControls(temporarily: false)
        }
        isShowingInfoPopover.toggle()
    }

    private var keyboardCommands: some View {
        HStack {
            Button(action: { toggleControlsVisibility() }) { EmptyView() }
                .keyboardShortcut("c", modifiers: [])

            Button {
                guard !dismissPauseScreen() else { return }
                toggleInfoPopover()
            } label: {
                EmptyView()
            }
            .keyboardShortcut("i", modifiers: [])

            Button {
                guard !dismissPauseScreen() else { return }
                keyboardSeek(by: -seekBackwardInterval)
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button(action: { togglePlayPauseFromKeyboard() }) { EmptyView() }
                .keyboardShortcut(.space, modifiers: [])

            Button {
                guard !dismissPauseScreen() else { return }
                keyboardSeek(by: seekForwardInterval)
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            if pauseScreen.isPresented {
                Button {
                    dismissPauseScreen()
                } label: {
                    EmptyView()
                }
                .keyboardShortcut(.escape, modifiers: [])
            } else if sleepTimer.isPromptPresented {
                Button {
                    sleepTimer.continueAfterPrompt()
                } label: {
                    EmptyView()
                }
                .keyboardShortcut(.escape, modifiers: [])
            } else if activeOffsetBar != nil {
                Button {
                    closeOffsetBar()
                } label: {
                    EmptyView()
                }
                .keyboardShortcut(.escape, modifiers: [])
            } else if isShowingPlayQueue {
                Button {
                    hidePlayQueue()
                } label: {
                    EmptyView()
                }
                .keyboardShortcut(.escape, modifiers: [])
            } else if !fullscreenCoordinator.isFullScreen {
                Button {
                    nextEpisodePresentation.cancel()
                    closePlayer()
                } label: {
                    EmptyView()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private var fullscreenAccessibilityLabel: String {
        if fullscreenCoordinator.isFullScreen {
            String(localized: "player.controls.exitFullscreen")
        } else {
            String(localized: "player.controls.enterFullscreen")
        }
    }

    private func toggleFullScreen() {
        fullscreenCoordinator.toggleFullScreen()
        showControls(temporarily: true)
    }

    private func configureController() {
        configureSleepTimer()
        playerController.onPictureInPictureRestoreRequested = {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: AppModel.playerWindowID)
        }
        playerController.onMediaLoaded = {
            viewModel.confirmLiveChannelSwitch()
            let tracks = playerController.trackList()
            audioTracks = tracks.filter { $0.type == .audio }
            subtitleTracks = tracks.filter { $0.type == .subtitle }
            if shouldRestoreTracksAfterLoad {
                let audioID = pendingRecoveryAudioProviderStreamID.flatMap { providerStreamID in
                    audioTracks.first { $0.providerStreamID == providerStreamID }?.id
                }
                let subtitleID = pendingRecoverySubtitleProviderStreamID.flatMap { providerStreamID in
                    subtitleTracks.first { $0.providerStreamID == providerStreamID }?.id
                }
                selectedAudioTrackID = audioID
                selectedSubtitleTrackID = subtitleID
                playerController.selectAudioTrack(id: audioID)
                playerController.selectSubtitleTrack(
                    id: subtitleID,
                    styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                )
                pendingRecoveryAudioProviderStreamID = nil
                pendingRecoverySubtitleProviderStreamID = nil
                shouldRestoreTracksAfterLoad = false
            } else {
                selectedAudioTrackID = audioTracks.first(where: \.isSelected)?.id

                if viewModel.preferredSubtitleSelectionIsOff {
                    selectedSubtitleTrackID = nil
                    playerController.selectSubtitleTrack(
                        id: nil,
                        styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                    )
                } else if let preferredSubtitle = viewModel.preferredSubtitleStreamID,
                          let track = subtitleTracks.first(where: { $0.providerStreamID == preferredSubtitle })
                {
                    selectedSubtitleTrackID = track.id
                    playerController.selectSubtitleTrack(
                        id: track.id,
                        styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                    )
                }
            }
            if participatesInSharePlay, sharePlayCoordinator.isInSession {
                sharePlayCoordinator.playerDidLoad(ratingKey: viewModel.currentRatingKey)
            }
            if shouldPauseAfterMediaLoad {
                shouldPauseAfterMediaLoad = false
                shouldResumeAfterMediaLoad = false
                playerController.pause()
            } else if shouldResumeAfterMediaLoad {
                shouldResumeAfterMediaLoad = false
                playerController.resume()
            }
            #if DEBUG
                showControls(temporarily: !DemoMode.isEnabled)
            #else
                showControls(temporarily: true)
            #endif
        }
        playerController.onPlaybackEnded = {
            Task { await handlePlaybackEnded() }
        }
    }

    private func startPlaybackIfNeeded(_ url: URL?) {
        guard let url, loadedURL != url else { return }
        loadedURL = url
        let isSharePlayPlayback = participatesInSharePlay && sharePlayCoordinator.isInSession
        let startPosition = isSharePlayPlayback
            ? sharePlayCoordinator.activity?.initialPosition
            : (viewModel.shouldResumeFromOffset ? viewModel.resumePosition : nil)
        playerController.load(
            url: url,
            httpHeaders: viewModel.playbackHTTPHeaders,
            startPosition: startPosition,
            preferredAudioTrackID: viewModel.preferredAudioStreamFFIndex,
            losslessAudio: settingsManager.playback.losslessAudio,
            spatialAudioLayout: settingsManager.playback.spatialAudioLayout,
            styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
            mediaIdentifier: viewModel.media?.id ?? url.lastPathComponent,
            providerStreamIDsByFFIndex: viewModel.providerStreamIDsByFFIndex(),
            externalSubtitles: viewModel.externalSubtitleTracks(),
            scrubThumbnailSource: viewModel.scrubThumbnailSource,
            showsScrubThumbnailPreviews: settingsManager.playback.showScrubThumbnailPreviews,
            generatesMissingScrubThumbnailPreviews:
            settingsManager.playback.generateMissingScrubThumbnailPreviews,
            showsSubtitlesOnSkipBack: settingsManager.playback.showSubtitlesOnSkipBack
                && !viewModel.isTranscoding,
            isLive: viewModel.isLivePlayback,
            nativeRemoteHLS: viewModel.liveNativeRemoteHLS,
            dvrWindowSeconds: viewModel.liveDVRWindowSeconds,
            audioDelayMilliseconds: settingsManager.playback.audioDelayMilliseconds,
            autoplay: !isSharePlayPlayback,
        )
        playerController.setPlaybackRate(playbackRate)
    }

    private func handleAutomaticMarkerSkipIfNeeded() {
        guard !isScrubbing, !(participatesInSharePlay && sharePlayCoordinator.isInSession),
              let marker = viewModel.automaticSkipMarker(
                  autoSkipIntros: settingsManager.playback.autoSkipIntros,
                  autoSkipCredits: settingsManager.playback.autoSkipCredits,
                  autoSkipCommercials: settingsManager.playback.autoSkipCommercials,
              )
        else {
            return
        }

        playerController.seek(to: marker.endTime)
        viewModel.position = marker.endTime
        scrubPosition = marker.endTime
        showAutomaticSkipFeedback(for: marker)
    }

    private func showAutomaticSkipFeedback(for marker: SkipSegment) {
        showFeedbackMessage(marker.automaticSkipConfirmation)
    }

    private func showFeedbackMessage(_ message: String, duration: TimeInterval = 2.5) {
        automaticSkipFeedbackWorkItem?.cancel()

        withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
            automaticSkipFeedbackMessage = message
        }

        let workItem = DispatchWorkItem {
            withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
                automaticSkipFeedbackMessage = nil
            }
        }
        automaticSkipFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func handlePlaybackEnded() async {
        let stopsForSleepTimer = sleepTimer.consumePlaybackEnd()
        await viewModel.markPlaybackFinished()

        if viewModel.media?.type == .episode {
            guard viewModel.usesCommonPlaybackQueue, let nextViewModel = viewModel.makeNextPlayerViewModel() else {
                if isSharePlayPlayback {
                    sharePlayCoordinator.leave()
                    participatesInSharePlay = false
                    closePlayer(force: true)
                } else {
                    playerController.pause()
                }
                return
            }

            if isSharePlayPlayback, let next = nextViewModel.media {
                sharePlayCoordinator.updateToNextItem(next)
                return
            }

            // The sleep timer asked to stop here: offer the next episode without counting down to it.
            let autoplay = stopsForSleepTimer ? .disabled : settingsManager.playback.nextEpisodeAutoplay
            if autoplay == .immediately {
                await startPlayback(using: nextViewModel)
            } else {
                nextEpisodePresentation.present(next: nextViewModel, mode: autoplay)
            }
            return
        }

        guard !stopsForSleepTimer,
              isSharePlayPlayback || settingsManager.playback.nextEpisodeAutoplay.isEnabled
        else {
            playerController.pause()
            return
        }

        if viewModel.usesCommonPlaybackQueue {
            guard let nextViewModel = viewModel.makeNextPlayerViewModel() else {
                playerController.pause()
                return
            }
            if isSharePlayPlayback, let next = nextViewModel.media {
                sharePlayCoordinator.updateToNextItem(next)
                return
            }
            await startPlayback(using: nextViewModel)
            return
        }

        if isSharePlayPlayback {
            sharePlayCoordinator.leave()
            participatesInSharePlay = false
            closePlayer(force: true)
        } else {
            playerController.pause()
        }
    }

    private func startPlayback(using nextViewModel: PlayerViewModel) async {
        playerController.stop()
        loadedURL = nil
        audioTracks = []
        subtitleTracks = []
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        viewModel = nextViewModel
        await viewModel.load()
        startPlaybackIfNeeded(viewModel.playbackURL)
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
        showControls(temporarily: false)
        playerController.pause()
    }

    private func switchLiveChannel(by offset: Int) {
        Task {
            do {
                let url = try await viewModel.switchLiveChannel(by: offset)
                playerController.stop()
                loadedURL = nil
                startPlaybackIfNeeded(url)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                LiveTVErrorReporting.capture(error)
                showError(String(localized: "livetv.playback.error"))
            }
        }
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
                showError(message)
                return
            }
        } catch let error as MediaServerAccessRecoveryError {
            presentServerRecoveryError(error)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            showError(message)
        }
    }

    private func reloadPlaybackAfterServerAccessChange(_ generation: Int) async {
        guard !viewModel.isLocalPlayback,
              generation != lastReloadedServerAccessGeneration,
              loadedURL != nil
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
        loadedURL = nil

        do {
            let url = try await viewModel.refreshPlaybackSource()
            let isSharePlay = participatesInSharePlay && sharePlayCoordinator.isInSession
            loadedURL = url
            playerController.load(
                url: url,
                httpHeaders: viewModel.playbackHTTPHeaders,
                startPosition: position,
                preferredAudioTrackID: viewModel.ffIndex(
                    forProviderStreamID: pendingRecoveryAudioProviderStreamID,
                ),
                losslessAudio: settingsManager.playback.losslessAudio,
                spatialAudioLayout: settingsManager.playback.spatialAudioLayout,
                styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                mediaIdentifier: viewModel.media?.id ?? url.lastPathComponent,
                providerStreamIDsByFFIndex: viewModel.providerStreamIDsByFFIndex(),
                externalSubtitles: viewModel.externalSubtitleTracks(),
                scrubThumbnailSource: viewModel.scrubThumbnailSource,
                showsScrubThumbnailPreviews: settingsManager.playback.showScrubThumbnailPreviews,
                generatesMissingScrubThumbnailPreviews:
                settingsManager.playback.generateMissingScrubThumbnailPreviews,
                showsSubtitlesOnSkipBack: settingsManager.playback.showSubtitlesOnSkipBack
                    && !viewModel.isTranscoding,
                isLive: viewModel.isLivePlayback,
                nativeRemoteHLS: viewModel.liveNativeRemoteHLS,
                dvrWindowSeconds: viewModel.liveDVRWindowSeconds,
                audioDelayMilliseconds: settingsManager.playback.audioDelayMilliseconds,
                autoplay: !isSharePlay,
            )
            playerController.setPlaybackRate(playbackRate)
            shouldResumeAfterMediaLoad = !isSharePlay && !wasPaused
            shouldPauseAfterMediaLoad = !isSharePlay && wasPaused
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
        loadedURL = nil
        if participatesInSharePlay, sharePlayCoordinator.isInSession {
            sharePlayCoordinator.leave()
            participatesInSharePlay = false
        }
        if let error, let server = viewModel.serverIdentity {
            sessionManager.handleTerminalServerAccessFailure(error, server: server)
        }
        closePlayer(force: true)
    }

    private func presentServerRecoveryError(_ error: MediaServerAccessRecoveryError) {
        playerController.pause()
        serverRecoveryError = error
        viewModel.clearServerAccessRecoveryError()
        isShowingServerRecoveryAlert = true
    }

    private func stopPlayback() {
        viewModel.handleStop()
        playerController.onPictureInPictureRestoreRequested = nil
        playerController.stop()
    }

    /// The stream is considered lost when there is no network at all, or when its server is unreachable and the
    /// player stalls; a single failed side request must not interrupt a stream that still plays.
    private var isStreamingServerUnreachable: Bool {
        guard let server = viewModel.streamingServer, offlineCoordinator.isUnreachable(server) else { return false }
        return !offlineCoordinator.availability.hasNetworkPath || playerController.isBuffering
    }

    /// Streaming cannot continue without its server: stop cleanly and offer the downloaded copy when there is one.
    private func handleStreamingServerLost() {
        guard !(participatesInSharePlay && sharePlayCoordinator.isInSession) else { return }
        playerController.pause()
        offlineHandoff = viewModel.prepareOfflineHandoff()
        viewModel.handleStop()
        isShowingOfflineInterruption = true
    }

    private func closePlayer(force: Bool = false) {
        hideControlsWorkItem?.cancel()
        if participatesInSharePlay, sharePlayCoordinator.isInSession, !force {
            isShowingSharePlayExitPrompt = true
            return
        }
        restoreCursor()
        stopPlayback()
        appModel.resetPlayer()
        dismissWindow(id: AppModel.playerWindowID)
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

    private func handlePointerMovement(_ phase: HoverPhase) {
        switch phase {
        case let .active(location):
            isPointerInsidePlayer = true
            // Hover also reports when the view tree changes under a still pointer, which must not dismiss the
            // pause screen.
            guard location != lastPointerLocation else { return }
            lastPointerLocation = location
            showControls(temporarily: true)
        case .ended:
            isPointerInsidePlayer = false
            lastPointerLocation = nil
            restoreCursor()
        }
    }

    /// Returns whether the pause screen was visible, in which case the input only dismisses it.
    @discardableResult
    private func dismissPauseScreen() -> Bool {
        guard pauseScreen.registerInteraction() else { return false }
        showControls(temporarily: true)
        return true
    }

    private var seekBackwardInterval: Double {
        Double(settingsManager.playback.seekBackwardSeconds)
    }

    private var seekForwardInterval: Double {
        Double(settingsManager.playback.seekForwardSeconds)
    }

    private func keyboardSeek(by seconds: Double) {
        guard !controlsVisible else {
            playerController.seek(by: seconds)
            return
        }

        let origin = playerController.seekOrigin
        playerController.seek(by: seconds)
        showSeekFeedback(.next(
            after: seekFeedback,
            forward: seconds > 0,
            origin: origin,
            target: playerController.seekOrigin,
        ))
    }

    private func showSeekFeedback(_ feedback: SeekFeedback) {
        seekFeedbackWorkItem?.cancel()
        seekFeedback = feedback

        let workItem = DispatchWorkItem {
            withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
                seekFeedback = nil
            }
        }

        seekFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seekFeedbackDelay, execute: workItem)
    }

    private func toggleControlsVisibility() {
        guard !dismissPauseScreen() else { return }
        if isShowingPlayQueue {
            hidePlayQueue()
            return
        }

        if controlsVisible {
            hideControls(force: true)
        } else {
            showControls(temporarily: true)
        }
    }

    private func showControls(temporarily: Bool) {
        pauseScreen.registerInteraction()
        guard !isShowingPlayQueue else { return }
        hideControlsWorkItem?.cancel()
        restoreCursor()
        withAnimation(Motion.animation(Motion.controls, reduceMotion: reduceMotion)) {
            controlsVisible = true
        }

        if temporarily {
            scheduleControlsHide()
        }
    }

    private func showPlayQueue() {
        guard viewModel.hasNavigableQueue, viewModel.artworkServices != nil else { return }
        hideControlsWorkItem?.cancel()
        restoreCursor()
        withAnimation(Motion.animation(Motion.panel, reduceMotion: reduceMotion)) {
            isShowingPlayQueue = true
            controlsVisible = false
        }
    }

    private func hidePlayQueue() {
        guard isShowingPlayQueue else { return }
        withAnimation(Motion.animation(Motion.panel, reduceMotion: reduceMotion)) {
            isShowingPlayQueue = false
        }
    }

    private func selectQueueItem(at index: Int) {
        guard let currentIndex = viewModel.queueCurrentIndex,
              index != currentIndex
        else {
            hidePlayQueue()
            return
        }

        guard let nextViewModel = viewModel.makePlayerViewModel(
            at: index,
            shouldResumeFromOffset: true,
        ) else { return }

        hidePlayQueue()
        Task {
            await startPlayback(using: nextViewModel)
        }
    }

    private var isPauseScreenEligible: Bool {
        settingsManager.playback.showInfoWhenPaused
            && playerController.isPaused
            && !playerController.isBuffering
            && !viewModel.isLoading
            && viewModel.media != nil
            && !isScrubbing
            && !isVoiceOverEnabled
            && !playerController.isPictureInPictureActive
            && !playerController.isPictureInPictureTransitioning
            && sheetPresentation.item == nil
            && !isShowingChapterPopover
            && !isShowingInfoPopover
            && !isShowingPlayQueue
            && activeOffsetBar == nil
            && !nextEpisodePresentation.isPresented
            && !sleepTimer.isPromptPresented
            && !isRecoveringServerAccess
            && !isShowingError
            && !isShowingServerRecoveryAlert
            && !isShowingOfflineInterruption
            && !isShowingSubtitleSearchError
            && qualityNoticeMessage == nil
            && viewModel.launchNotice == nil
            && !isShowingSharePlayExitPrompt
    }

    private func scheduleControlsHide() {
        hideControlsWorkItem?.cancel()
        guard
            !isShowingPlayQueue,
            !playerController.isPaused,
            !isScrubbing,
            !isShowingError,
            !isShowingChapterPopover,
            !isShowingInfoPopover,
            activeOffsetBar == nil
        else {
            return
        }

        let workItem = DispatchWorkItem {
            hideControls(force: false)
        }
        hideControlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + controlsHideDelay, execute: workItem)
    }

    private func hideControls(force: Bool) {
        hideControlsWorkItem?.cancel()
        guard
            force || (
                !playerController.isPaused
                    && !isScrubbing
                    && !isShowingError
                    && !isShowingChapterPopover
                    && !isShowingInfoPopover
                    && activeOffsetBar == nil
            )
        else {
            return
        }

        withAnimation(Motion.animation(Motion.controls, reduceMotion: reduceMotion)) {
            controlsVisible = false
        }
        if isPointerInsidePlayer {
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func restoreCursor() {
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func selectChapter(_ chapter: MediaChapter) {
        playerController.seek(to: chapter.startTime)
        scrubPosition = chapter.startTime
        viewModel.handlePlaybackPosition(chapter.startTime, isScrubbing: false)
        isShowingChapterPopover = false
    }
}

private enum PlayerSheet: String, Identifiable {
    case subtitleSearch

    var id: String {
        rawValue
    }
}
