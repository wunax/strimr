import AetherEngine
import SwiftUI

struct PlayerTVView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlexAPIContext.self) private var context
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(WatchTogetherViewModel.self) private var watchTogetherViewModel
    @State var viewModel: PlayerViewModel
    let onExit: () -> Void
    @State private var playerController = AetherPlayerController()
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var isScrubbing = false
    @State private var videoFormatBadge: PlayerVideoFormatBadge?
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
    @State private var activeSettingsSheet: PlayerSettingsSheet?
    @State private var seekFeedback: SeekFeedback?
    @State private var seekFeedbackWorkItem: DispatchWorkItem?
    @State private var showingTerminationAlert = false
    @State private var terminationAlertMessage = ""
    @State private var wasInWatchTogetherSession = false
    @State private var activePlaybackURL: URL?
    @State private var needsPlaybackReloadAfterBackground = false
    @State private var backgroundPlaybackPosition: Double?
    @State private var wasPlayingBeforeBackground = false
    @State private var shouldResumeAfterMediaLoad = false
    @State private var shouldPauseAfterMediaLoad = false
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
                startPlaybackIfNeeded(url: viewModel.playbackURL)
                if watchTogetherViewModel.isInSession {
                    watchTogetherViewModel.attachPlayerController(playerController)
                    wasInWatchTogetherSession = true
                }
            }
            .onDisappear {
                viewModel.handleStop()
                hideControlsWorkItem?.cancel()
                seekFeedbackWorkItem?.cancel()
                playerController.stop()
                if wasInWatchTogetherSession {
                    watchTogetherViewModel.detachPlayerController()
                }
            }
            .onPlayPauseCommand {
                togglePlayPause()
            }
            .onExitCommand {
                if watchTogetherViewModel.isInSession {
                    watchTogetherViewModel.leaveSession(endForAll: false)
                }
                dismissPlayer(force: true)
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
            .onChange(of: watchTogetherViewModel.isInSession) { _, newValue in
                guard wasInWatchTogetherSession, !newValue else { return }
                watchTogetherViewModel.detachPlayerController()
            }
            .onChange(of: watchTogetherViewModel.sessionEndedSignal) { _, _ in
                guard wasInWatchTogetherSession else { return }
                dismissPlayer(force: true)
            }
            .onChange(of: watchTogetherViewModel.playbackStoppedSignal) { _, _ in
                guard wasInWatchTogetherSession else { return }
                dismissPlayer(force: true)
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
    }

    private var playerScene: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AetherPlayerSurface(engine: playerController.engine)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            SubtitleOverlayView(
                cues: playerController.subtitleCues,
                currentTime: playerController.sourcePosition,
                maxCueDuration: playerController.subtitleMaxCueDuration,
                subtitleFontSize: settingsManager.playback.subtitleFontSize,
                controlsVisible: controlsVisible,
            )
            .ignoresSafeArea()
        }
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

            if viewModel.isBuffering {
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
                    isScrubbing: isScrubbing,
                    onShowAudioSettings: showAudioSettings,
                    onShowSubtitleSettings: showSubtitleSettings,
                    onShowSpeedSettings: showSpeedSettings,
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
                    isWatchTogether: watchTogetherViewModel.isInSession,
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

            ToastOverlay(toasts: watchTogetherViewModel.toasts)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                onClose: { activeSettingsSheet = nil },
            )
        case .speed:
            PlayerSpeedSelectionView(
                selectedRate: playbackRate,
                onSelect: selectPlaybackRate(_:),
                onClose: { activeSettingsSheet = nil },
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
        let wasPaused = viewModel.isPaused
        playerController.togglePlayback()
        showControls(temporarily: true)
        watchTogetherViewModel.sendPlayPause(isCurrentlyPaused: wasPaused)
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
        watchTogetherViewModel.sendRateChange(rate)
    }

    private func jump(by seconds: Double) {
        playerController.seek(by: seconds)
        showControls(temporarily: true)
        let newPosition = max(0, viewModel.position + seconds)
        watchTogetherViewModel.sendSeek(to: newPosition)
    }

    private func quickSeek(by seconds: Double) {
        playerController.seek(by: seconds)
        showSeekFeedback(forward: seconds > 0, seconds: Int(abs(seconds)))
    }

    private func applyResumeOffsetIfNeeded() {
        guard viewModel.shouldResumeFromOffset else { return }
        guard !appliedResumeOffset, let offset = viewModel.resumePosition, offset > 0 else { return }
        appliedResumeOffset = true
        playerController.seek(to: offset)
    }

    private func handleMediaLoaded() {
        guard awaitingMediaLoad else { return }
        awaitingMediaLoad = false
        refreshTracks()
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
            hideControlsWorkItem?.cancel()
            withAnimation(.easeInOut) {
                controlsVisible = true
            }
        } else {
            playerController.seek(to: timelinePosition)
            viewModel.position = timelinePosition
            scheduleControlsHide()
            watchTogetherViewModel.sendSeek(to: timelinePosition)
        }
    }

    private func startPlaybackIfNeeded(url: URL?) {
        guard let url else { return }
        guard activePlaybackURL != url else { return }

        let startPosition = viewModel.shouldResumeFromOffset ? viewModel.resumePosition : nil
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

        if temporarily, !isScrubbing {
            scheduleControlsHide()
        } else {
            hideControlsWorkItem?.cancel()
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
            playerController.selectAudioTrack(id: track.id)
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
        watchTogetherViewModel.sendSeek(to: marker.endTime)
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
            HStack(spacing: 12) {
                Image(systemName: feedback.systemImage)
                    .font(.title2.weight(.semibold))
                Text(feedback.text)
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.7), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1),
            )
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

        guard settingsManager.playback.autoPlayNextEpisode else {
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

    private func syncPlaybackState() {
        viewModel.handlePlaybackState(
            isPaused: playerController.isPaused,
            isBuffering: playerController.isBuffering,
        )
    }
}

private enum PlayerSettingsSheet: String, Identifiable {
    case audio
    case subtitle
    case speed

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
        }
    }
}

private struct SeekFeedback: Equatable {
    let forward: Bool
    let seconds: Int

    var text: String {
        if forward {
            return String(localized: "player.controls.skipForwardSeconds \(seconds)")
        }
        return String(localized: "player.controls.rewindSeconds \(seconds)")
    }

    var systemImage: String {
        forward ? "goforward" : "gobackward"
    }
}

private enum PlayerFocusTarget: Hashable {
    case controlsProxy
    case skipOverlay
}
