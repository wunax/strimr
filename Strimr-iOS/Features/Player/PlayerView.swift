import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlexAPIContext.self) private var context
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @State var viewModel: PlayerViewModel
    @State private var playerController = PlayerController()
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var isScrubbing = false
    @State private var videoFormatBadge: PlayerVideoFormatBadge?
    @State private var showingSettings = false
    @State private var audioTracks: [PlayerTrack] = []
    @State private var subtitleTracks: [PlayerTrack] = []
    @State private var settingsAudioTracks: [PlaybackSettingsTrack] = []
    @State private var settingsSubtitleTracks: [PlaybackSettingsTrack] = []
    @State private var selectedAudioTrackID: Int?
    @State private var selectedSubtitleTrackID: Int?
    @State private var playbackRate: Float = 1.0
    @State private var appliedPreferredAudio = false
    @State private var appliedPreferredSubtitle = false
    @State private var appliedResumeOffset = false
    @State private var awaitingMediaLoad = false
    @State private var timelinePosition = 0.0
    @State private var showingTerminationAlert = false
    @State private var terminationAlertMessage = ""
    @State private var isRotationLocked = false
    @State private var isShowingSharePlayExitPrompt = false
    @State private var activePlaybackURL: URL?
    @State private var needsPlaybackReloadAfterBackground = false
    @State private var backgroundPlaybackPosition: Double?
    @State private var wasPlayingBeforeBackground = false
    @State private var shouldResumeAfterMediaLoad = false
    @State private var shouldPauseAfterMediaLoad = false

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
                    playerController.stop()
                    AppDelegate.orientationLock = .all
                    isRotationLocked = false
                    if sharePlayCoordinator.isInSession {
                        sharePlayCoordinator.leave()
                    }
                }
                .task {
                    await viewModel.load()
                },
        )

        let playbackObservers = AnyView(
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
                    terminationAlertMessage = newValue
                    showingTerminationAlert = true
                    playerController.pause()
                }
                .onChange(of: viewModel.position) { _, newValue in
                    guard !isScrubbing else { return }
                    timelinePosition = newValue
                }
                .onChange(of: viewModel.terminationMessage) { _, newValue in
                    guard let newValue else { return }
                    terminationAlertMessage = newValue
                    showingTerminationAlert = true
                    playerController.pause()
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
            .sheet(isPresented: $showingSettings) {
                playbackSettingsSheet
            }
            .alert("player.termination.title", isPresented: $showingTerminationAlert) {
                Button("player.termination.dismiss") {
                    dismissPlayer(force: true)
                }
            } message: {
                Text(terminationAlertMessage)
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
                currentTime: playerController.sourcePosition,
                maxCueDuration: playerController.subtitleMaxCueDuration,
                subtitleFontSize: settingsManager.playback.subtitleFontSize,
                controlsVisible: controlsVisible,
                videoSize: playerController.sourceVideoSize,
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
                    controlsVisible ? hideControls() : showControls(temporarily: true)
                }

            if viewModel.isBuffering {
                bufferingOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            if controlsVisible {
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
                    isScrubbing: isScrubbing,
                    onDismiss: { dismissPlayer() },
                    onShowSettings: showSettings,
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
                )
                .transition(.opacity)
            }

            if !controlsVisible, let activeMarker, let skipTitle {
                skipOverlay(marker: activeMarker, title: skipTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    private var playbackSettingsSheet: some View {
        PlaybackSettingsView(
            audioTracks: settingsAudioTracks,
            subtitleTracks: settingsSubtitleTracks,
            selectedAudioTrackID: selectedAudioTrackID,
            selectedSubtitleTrackID: selectedSubtitleTrackID,
            playbackRate: playbackRate,
            onSelectAudio: selectAudioTrack(_:),
            onSelectSubtitle: selectSubtitleTrack(_:),
            onSelectPlaybackRate: selectPlaybackRate(_:),
            onClose: { showingSettings = false },
        )
        .presentationDetents([.medium])
        .presentationBackground(.ultraThinMaterial)
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

    private func showSettings() {
        refreshTracks()
        showingSettings = true
        hideControlsWorkItem?.cancel()
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
            let tracks = playerController.trackList()

            let audio = tracks.filter { $0.type == .audio }
            let subtitles = tracks.filter { $0.type == .subtitle }

            await MainActor.run {
                audioTracks = audio
                subtitleTracks = subtitles

                settingsAudioTracks = audio.map {
                    PlaybackSettingsTrack(
                        track: $0,
                        plexStream: viewModel.plexStream(forFFIndex: $0.ffIndex),
                    )
                }

                settingsSubtitleTracks = subtitles.map {
                    PlaybackSettingsTrack(
                        track: $0,
                        plexStream: viewModel.plexStream(forFFIndex: $0.ffIndex),
                    )
                }

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
        playerController.selectSubtitleTrack(id: id)

        guard
            let id,
            let track = subtitleTracks.first(where: { $0.id == id })
        else {
            return
        }

        Task {
            await viewModel.persistStreamSelection(for: track)
        }
    }

    private func selectPlaybackRate(_ rate: Float) {
        playbackRate = rate
        playerController.setPlaybackRate(rate)
        showControls(temporarily: true)
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
            hideControlsWorkItem?.cancel()
            withAnimation(.easeInOut) {
                controlsVisible = true
            }
        } else {
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
           let preferredSubtitleIndex = viewModel.preferredSubtitleStreamFFIndex,
           let track = subtitleTracks.first(where: { $0.ffIndex == preferredSubtitleIndex })
        {
            selectedSubtitleTrackID = track.id
            playerController.selectSubtitleTrack(id: track.id)
            appliedPreferredSubtitle = true
        }
    }

    private func skipMarker(to marker: PlexMarker) {
        playerController.seek(to: marker.endTime)
        viewModel.position = marker.endTime
        timelinePosition = marker.endTime
        showControls(temporarily: true)
    }

    private func skipOverlay(marker: PlexMarker, title: String) -> some View {
        SkipMarkerButton(title: title) {
            skipMarker(to: marker)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    private func handlePlaybackEnded() {
        guard let media = viewModel.media else {
            dismissPlayer(force: true)
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
            dismissPlayer(force: true)
        }
    }

    private func handleEpisodeCompletion(for _: MediaItem) async {
        await viewModel.markPlaybackFinished()

        guard sharePlayCoordinator.isInSession || settingsManager.playback.autoPlayNextEpisode else {
            await MainActor.run {
                dismissPlayer(force: true)
            }
            return
        }

        guard let nextItem = await viewModel.nextItemInQueue() else {
            await MainActor.run {
                dismissPlayer(force: true)
            }
            return
        }

        if sharePlayCoordinator.isInSession {
            await MainActor.run {
                sharePlayCoordinator.updateToNextEpisode(nextItem)
            }
            return
        }

        await startPlayback(of: nextItem)
    }

    private func handleMovieCompletion() async {
        await viewModel.markPlaybackFinished()

        guard let nextItem = await viewModel.nextItemInQueue() else {
            await MainActor.run {
                dismissPlayer(force: true)
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
}
