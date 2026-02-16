import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlexAPIContext.self) private var context
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(WatchTogetherViewModel.self) private var watchTogetherViewModel
    @Environment(SharePlayViewModel.self) private var sharePlayViewModel
    @State var viewModel: PlayerViewModel
    let activePlayer: InternalPlaybackPlayer
    @State private var playerCoordinator: any PlayerCoordinating
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var isScrubbing = false
    @State private var supportsHDR = false
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
    @State private var isShowingWatchTogetherExitPrompt = false
    @State private var wasInWatchTogetherSession = false
    @State private var wasInSharePlaySession = false
    @State private var activePlaybackURL: URL?

    private let controlsHideDelay: TimeInterval = 3.0
    private var seekBackwardInterval: Double {
        Double(settingsManager.playback.seekBackwardSeconds)
    }

    private var seekForwardInterval: Double {
        Double(settingsManager.playback.seekForwardSeconds)
    }

    init(viewModel: PlayerViewModel, initialPlayer: InternalPlaybackPlayer, options: PlayerOptions) {
        _viewModel = State(initialValue: viewModel)
        activePlayer = initialPlayer
        _playerCoordinator = State(initialValue: PlayerFactory.makeCoordinator(for: initialPlayer, options: options))
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel
        let activeMarker = bindableViewModel.activeSkipMarker
        let skipTitle = activeMarker.flatMap { marker in
            marker.isCredits
                ? String(localized: "player.skip.credits")
                : String(localized: "player.skip.intro")
        }

        ZStack {
            Color.black.ignoresSafeArea()

            PlayerFactory.makeView(
                selection: activePlayer,
                coordinator: playerCoordinator,
                onPropertyChange: { propertyName, data in
                    bindableViewModel.handlePropertyChange(
                        property: propertyName,
                        data: data,
                        isScrubbing: isScrubbing,
                    )

                    if propertyName == .videoParamsSigPeak {
                        let supportsHdr = (data as? Double ?? 1.0) > 1.0
                        supportsHDR = supportsHdr
                    }
                },
                onPlaybackEnded: {
                    handlePlaybackEnded()
                },
                onMediaLoaded: {
                    handleMediaLoaded()
                },
            )
            .onAppear {
                showControls(temporarily: true)
            }
            .ignoresSafeArea()
        }
        .statusBarHidden()
        .overlay {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        controlsVisible ? hideControls() : showControls(temporarily: true)
                    }

                if bindableViewModel.isBuffering {
                    bufferingOverlay
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                if controlsVisible {
                    PlayerControlsView(
                        media: bindableViewModel.media,
                        isPaused: bindableViewModel.isPaused,
                        isBuffering: bindableViewModel.isBuffering,
                        videoResolution: bindableViewModel.media?.playbackResolutionLabel,
                        supportsHDR: supportsHDR,
                        position: timelineBinding,
                        duration: bindableViewModel.duration,
                        bufferedAhead: bindableViewModel.bufferedAhead,
                        bufferBasePosition: bindableViewModel.position,
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
                        isWatchTogether: watchTogetherViewModel.isInSession || sharePlayViewModel.isInSession,
                    )
                    .transition(.opacity)
                }

                if !controlsVisible, let activeMarker, let skipTitle {
                    skipOverlay(marker: activeMarker, title: skipTitle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                ToastOverlay(toasts: watchTogetherViewModel.toasts + sharePlayViewModel.toasts)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear {
            showControls(temporarily: true)
            playerCoordinator.setPlaybackRate(playbackRate)
            startPlaybackIfNeeded(url: bindableViewModel.playbackURL)
            if watchTogetherViewModel.isInSession {
                watchTogetherViewModel.attachPlayerCoordinator(playerCoordinator)
                wasInWatchTogetherSession = true
            }
            if sharePlayViewModel.isInSession {
                sharePlayViewModel.attachPlayerCoordinator(playerCoordinator)
                wasInSharePlaySession = true
            }
        }
        .onDisappear {
            viewModel.handleStop()
            hideControlsWorkItem?.cancel()
            playerCoordinator.destruct()
            AppDelegate.orientationLock = .all
            isRotationLocked = false
            if wasInWatchTogetherSession {
                watchTogetherViewModel.detachPlayerCoordinator()
            }
            if wasInSharePlaySession {
                sharePlayViewModel.detachPlayerCoordinator()
            }
        }
        .task {
            await bindableViewModel.load()
        }
        .onChange(of: bindableViewModel.playbackURL) { _, newURL in
            startPlaybackIfNeeded(url: newURL)
        }
        .onChange(of: bindableViewModel.position) { _, newValue in
            guard !isScrubbing else { return }
            timelinePosition = newValue
        }
        .onChange(of: bindableViewModel.terminationMessage) { _, newValue in
            guard let newValue else { return }
            terminationAlertMessage = newValue
            showingTerminationAlert = true
            playerCoordinator.pause()
        }
        .onChange(of: watchTogetherViewModel.isInSession) { _, newValue in
            guard wasInWatchTogetherSession, !newValue else { return }
            watchTogetherViewModel.detachPlayerCoordinator()
        }
        .onChange(of: watchTogetherViewModel.sessionEndedSignal) { _, _ in
            guard wasInWatchTogetherSession else { return }
            dismissPlayer(force: true)
        }
        .onChange(of: watchTogetherViewModel.playbackStoppedSignal) { _, _ in
            guard wasInWatchTogetherSession else { return }
            dismissPlayer(force: true)
        }
        .onChange(of: sharePlayViewModel.sessionEndedSignal) { _, _ in
            guard wasInSharePlaySession else { return }
            dismissPlayer(force: true)
        }
        .sheet(isPresented: $showingSettings) {
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
        .alert("player.termination.title", isPresented: $showingTerminationAlert) {
            Button("player.termination.dismiss") {
                dismissPlayer(force: true)
            }
        } message: {
            Text(terminationAlertMessage)
        }
        .confirmationDialog("watchTogether.exit.title", isPresented: $isShowingWatchTogetherExitPrompt) {
            if watchTogetherViewModel.isHost {
                Button("watchTogether.exit.stopForAll") {
                    watchTogetherViewModel.stopPlaybackForEveryone()
                    dismissPlayer(force: true)
                }

                Button("watchTogether.exit.endForAll", role: .destructive) {
                    watchTogetherViewModel.leaveSession(endForAll: true)
                    dismissPlayer(force: true)
                }
            }

            Button("watchTogether.exit.leave") {
                watchTogetherViewModel.leaveSession(endForAll: false)
                dismissPlayer(force: true)
            }

            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("watchTogether.exit.message")
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

    private var timelineBinding: Binding<Double> {
        Binding(
            get: { timelinePosition },
            set: { timelinePosition = $0 },
        )
    }

    private func togglePlayPause() {
        let wasPaused = viewModel.isPaused
        playerCoordinator.togglePlayback()
        showControls(temporarily: true)
        watchTogetherViewModel.sendPlayPause(isCurrentlyPaused: wasPaused)
        sharePlayViewModel.sendPlayPause(isCurrentlyPaused: wasPaused)
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
            let tracks = playerCoordinator.trackList()

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
        playerCoordinator.selectAudioTrack(id: id)

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
        playerCoordinator.selectSubtitleTrack(id: id)

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
        playerCoordinator.setPlaybackRate(rate)
        showControls(temporarily: true)
        watchTogetherViewModel.sendRateChange(rate)
        sharePlayViewModel.sendRateChange(rate)
    }

    private func jump(by seconds: Double) {
        playerCoordinator.seek(by: seconds)
        showControls(temporarily: true)
        let newPosition = max(0, viewModel.position + seconds)
        watchTogetherViewModel.sendSeek(to: newPosition)
        sharePlayViewModel.sendSeek(to: newPosition)
    }

    private func applyResumeOffsetIfNeeded() {
        guard viewModel.shouldResumeFromOffset else { return }
        guard !appliedResumeOffset, let offset = viewModel.resumePosition, offset > 0 else { return }
        appliedResumeOffset = true
        playerCoordinator.seek(to: offset)
    }

    private func handleMediaLoaded() {
        guard awaitingMediaLoad else { return }
        awaitingMediaLoad = false
        refreshTracks()
        applyResumeOffsetIfNeeded()
    }

    private func dismissPlayer(force: Bool = false) {
        hideControlsWorkItem?.cancel()
        if watchTogetherViewModel.isInSession, !force {
            isShowingWatchTogetherExitPrompt = true
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
            playerCoordinator.seek(to: timelinePosition)
            viewModel.position = timelinePosition
            scheduleControlsHide()
            watchTogetherViewModel.sendSeek(to: timelinePosition)
            sharePlayViewModel.sendSeek(to: timelinePosition)
        }
    }

    private func startPlaybackIfNeeded(url: URL?) {
        guard let url else { return }
        guard activePlaybackURL != url else { return }

        activePlaybackURL = url
        appliedPreferredAudio = false
        appliedPreferredSubtitle = false
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        appliedResumeOffset = false
        awaitingMediaLoad = true
        playerCoordinator.play(url)
        playerCoordinator.setPlaybackRate(playbackRate)
        showControls(temporarily: true)
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
            playerCoordinator.selectAudioTrack(id: track.id)
            appliedPreferredAudio = true
        }

        if !appliedPreferredSubtitle,
           let preferredSubtitleIndex = viewModel.preferredSubtitleStreamFFIndex,
           let track = subtitleTracks.first(where: { $0.ffIndex == preferredSubtitleIndex })
        {
            selectedSubtitleTrackID = track.id
            playerCoordinator.selectSubtitleTrack(id: track.id)
            appliedPreferredSubtitle = true
        }
    }

    private func skipMarker(to marker: PlexMarker) {
        playerCoordinator.seek(to: marker.endTime)
        viewModel.position = marker.endTime
        timelinePosition = marker.endTime
        showControls(temporarily: true)
        watchTogetherViewModel.sendSeek(to: marker.endTime)
        sharePlayViewModel.sendSeek(to: marker.endTime)
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

        guard settingsManager.playback.autoPlayNextEpisode else {
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
            viewModel = PlayerViewModel(
                playQueue: viewModel.playQueue,
                ratingKey: episode.ratingKey,
                context: context,
            )
        }

        await viewModel.load()
    }
}
