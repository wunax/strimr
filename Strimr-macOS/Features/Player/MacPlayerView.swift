import AppKit
import SwiftUI

struct MacPlayerWindowView: View {
    @Environment(PlexAPIContext.self) private var context
    @Environment(MacAppModel.self) private var appModel

    var body: some View {
        Group {
            if let presentation = appModel.playerPresentation,
               let ratingKey = presentation.playQueue.selectedRatingKey
            {
                MacPlayerView(
                    viewModel: playerViewModel(for: presentation, ratingKey: ratingKey),
                    presentationID: presentation.id,
                )
                .id(presentation.id)
            } else {
                ContentUnavailableView("player.window.title", systemImage: "play.rectangle")
            }
        }
    }

    private func playerViewModel(
        for presentation: MacAppModel.PlayerPresentation,
        ratingKey: String,
    ) -> PlayerViewModel {
        if let media = presentation.localMedia, let url = presentation.localPlaybackURL {
            return PlayerViewModel(localMedia: media, localPlaybackURL: url, context: context)
        }
        return PlayerViewModel(
            playQueue: presentation.playQueue,
            ratingKey: ratingKey,
            context: context,
            shouldResumeFromOffset: presentation.shouldResumeFromOffset,
        )
    }
}

struct MacPlayerView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(PlexAPIContext.self) private var context
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(MacAppModel.self) private var appModel
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator

    @State private var viewModel: PlayerViewModel
    @State private var playerController = PlayerController()
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var isPointerInsidePlayer = false
    @State private var isScrubbing = false
    @State private var scrubPosition = 0.0
    @State private var audioTracks: [PlayerTrack] = []
    @State private var subtitleTracks: [PlayerTrack] = []
    @State private var selectedAudioTrackID: Int?
    @State private var selectedSubtitleTrackID: Int?
    @State private var playbackRate: Float = 1
    @State private var loadedURL: URL?
    @State private var isShowingError = false
    @State private var errorMessage = ""
    @State private var isShowingSharePlayExitPrompt = false
    @State private var participatesInSharePlay = false

    private let presentationID: UUID
    private let controlsHideDelay: TimeInterval = 3

    init(viewModel: PlayerViewModel, presentationID: UUID) {
        _viewModel = State(initialValue: viewModel)
        self.presentationID = presentationID
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerSurfaceView(controller: playerController)
                .ignoresSafeArea()

            SubtitleOverlayView(
                cues: playerController.subtitleCues,
                currentTime: playerController.sourcePosition,
                maxCueDuration: playerController.subtitleMaxCueDuration,
                appearance: settingsManager.playback.subtitleAppearance,
                controlsVisible: controlsVisible,
                videoSize: playerController.sourceVideoSize,
            )
            .ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControlsVisibility() }

            if viewModel.isLoading || viewModel.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if controlsVisible {
                controls
                    .transition(.opacity)
            }

            keyboardCommands
        }
        .background(.black)
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
            await viewModel.load()
            startPlaybackIfNeeded(viewModel.playbackURL)
        }
        .onChange(of: viewModel.playbackURL) { _, url in
            startPlaybackIfNeeded(url)
        }
        .onChange(of: playerController.isPaused) { _, isPaused in
            viewModel.handlePlaybackState(isPaused: isPaused, isBuffering: playerController.isBuffering)
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
            if !isScrubbing {
                scrubPosition = position
            }
            viewModel.handlePlaybackPosition(position, isScrubbing: isScrubbing)
        }
        .onChange(of: playerController.duration) { _, duration in
            viewModel.handlePlaybackDuration(duration)
        }
        .onChange(of: playerController.bufferedAhead) { _, bufferedAhead in
            viewModel.handleBufferedAhead(bufferedAhead)
        }
        .onChange(of: playerController.errorMessage) { _, error in
            guard let error else { return }
            showError(error)
        }
        .onChange(of: viewModel.terminationMessage) { _, error in
            guard let error else { return }
            showError(error)
        }
        .onChange(of: sharePlayCoordinator.activityChangeID) { _, _ in
            guard participatesInSharePlay,
                  let activity = sharePlayCoordinator.activity,
                  activity.ratingKey != viewModel.currentRatingKey
            else { return }
            Task { await startPlayback(for: activity) }
        }
        .onDisappear {
            hideControlsWorkItem?.cancel()
            restoreCursor()
            stopPlayback()
            appModel.resetPlayer(ifPresenting: presentationID)
            if participatesInSharePlay, sharePlayCoordinator.isInSession {
                sharePlayCoordinator.leave()
            }
            participatesInSharePlay = false
        }
        .alert("player.termination.title", isPresented: $isShowingError) {
            Button("player.termination.dismiss") { closePlayer(force: true) }
        } message: {
            Text(errorMessage)
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(media.primaryLabel).font(.title3.bold())
                        if let secondary = media.tertiaryLabel ?? media.secondaryLabel {
                            Text(secondary).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if let badge = playerController.videoFormatBadge {
                    PlayerBadge(badge.title)
                }
                if participatesInSharePlay, sharePlayCoordinator.isInSession {
                    PlayerBadge(String(localized: "sharePlay.badge"))
                }
                Button("common.actions.close", systemImage: "xmark") {
                    closePlayer()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
            }

            Spacer()

            VStack(spacing: 14) {
                if let marker = viewModel.activeSkipMarker {
                    HStack {
                        Spacer()
                        Button(marker.isIntro ? "player.skip.intro" : "player.skip.credits") {
                            playerController.seek(to: marker.endTime / 1000)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                HStack(spacing: 10) {
                    Text(formatTime(scrubPosition))
                        .font(.caption.monospacedDigit())
                        .frame(width: 64, alignment: .trailing)
                    Slider(
                        value: $scrubPosition,
                        in: 0 ... max(viewModel.duration ?? 1, 1),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if editing {
                                showControls(temporarily: false)
                            }
                            if !editing {
                                playerController.seek(to: scrubPosition)
                                viewModel.handlePlaybackPosition(scrubPosition, isScrubbing: false)
                                showControls(temporarily: true)
                            }
                        },
                    )
                    Text(formatTime(viewModel.duration ?? 0))
                        .font(.caption.monospacedDigit())
                        .frame(width: 64, alignment: .leading)
                }

                HStack(spacing: 18) {
                    Button {
                        playerController.seek(by: -Double(settingsManager.playback.seekBackwardSeconds))
                    } label: {
                        Image(systemName: "gobackward.\(settingsManager.playback.seekBackwardSeconds)")
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    Button {
                        playerController.togglePlayback()
                    } label: {
                        Image(systemName: playerController.isPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.space, modifiers: [])

                    Button {
                        playerController.seek(by: Double(settingsManager.playback.seekForwardSeconds))
                    } label: {
                        Image(systemName: "goforward.\(settingsManager.playback.seekForwardSeconds)")
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])

                    Spacer()

                    volumeControl
                    audioMenu
                    subtitleMenu
                    speedMenu
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom,
            ),
        )
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
                    Button {
                        selectedAudioTrackID = track.id
                        playerController.selectAudioTrack(id: track.id)
                    } label: {
                        if selectedAudioTrackID == track.id {
                            Label(track.displayName, systemImage: "checkmark")
                        } else {
                            Text(track.displayName)
                        }
                    }
                }
            }
        } label: {
            Label("player.settings.audio", systemImage: "waveform")
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Button {
                selectedSubtitleTrackID = nil
                playerController.selectSubtitleTrack(id: nil)
            } label: {
                if selectedSubtitleTrackID == nil {
                    Label("player.settings.subtitles.off", systemImage: "checkmark")
                } else {
                    Text("player.settings.subtitles.off")
                }
            }
            ForEach(subtitleTracks) { track in
                Button {
                    selectedSubtitleTrackID = track.id
                    playerController.selectSubtitleTrack(id: track.id)
                } label: {
                    if selectedSubtitleTrackID == track.id {
                        Label(track.displayName, systemImage: "checkmark")
                    } else {
                        Text(track.displayName)
                    }
                }
            }
        } label: {
            Label("player.settings.subtitles", systemImage: "captions.bubble")
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlaybackSpeedOptions.all) { option in
                Button {
                    playbackRate = option.rate
                    playerController.setPlaybackRate(option.rate)
                } label: {
                    if playbackRate == option.rate {
                        Label("player.settings.speed.value \(option.valueText)", systemImage: "checkmark")
                    } else {
                        Text("player.settings.speed.value \(option.valueText)")
                    }
                }
            }
        } label: {
            Label("player.settings.speed", systemImage: "speedometer")
        }
    }

    private var keyboardCommands: some View {
        HStack {
            Button(action: { toggleControlsVisibility() }) { EmptyView() }
                .keyboardShortcut("c", modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func configureController() {
        playerController.onMediaLoaded = {
            let tracks = playerController.trackList()
            audioTracks = tracks.filter { $0.type == .audio }
            subtitleTracks = tracks.filter { $0.type == .subtitle }
            selectedAudioTrackID = audioTracks.first(where: \.isSelected)?.id

            if let preferredSubtitle = viewModel.preferredSubtitleStreamFFIndex,
               let track = subtitleTracks.first(where: { $0.ffIndex == preferredSubtitle })
            {
                selectedSubtitleTrackID = track.id
                playerController.selectSubtitleTrack(id: track.id)
            }
            if participatesInSharePlay, sharePlayCoordinator.isInSession {
                sharePlayCoordinator.playerDidLoad(ratingKey: viewModel.currentRatingKey)
            }
            showControls(temporarily: true)
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
            startPosition: startPosition,
            preferredAudioTrackID: viewModel.preferredAudioStreamFFIndex,
            losslessAudio: settingsManager.playback.losslessAudio,
            autoplay: !isSharePlayPlayback,
        )
        playerController.setPlaybackRate(playbackRate)
    }

    private func handlePlaybackEnded() async {
        await viewModel.markPlaybackFinished()
        let isSharePlayPlayback = participatesInSharePlay && sharePlayCoordinator.isInSession
        guard isSharePlayPlayback || settingsManager.playback.autoPlayNextEpisode else {
            playerController.pause()
            return
        }

        guard let next = await viewModel.nextItemInQueue() else {
            if isSharePlayPlayback {
                sharePlayCoordinator.leave()
                participatesInSharePlay = false
                closePlayer(force: true)
            } else {
                playerController.pause()
            }
            return
        }

        if isSharePlayPlayback {
            sharePlayCoordinator.updateToNextEpisode(next)
            return
        }

        let nextViewModel = PlayerViewModel(
            playQueue: viewModel.playQueue,
            ratingKey: next.ratingKey,
            context: context,
            shouldResumeFromOffset: false,
        )
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

    private func stopPlayback() {
        viewModel.handleStop()
        playerController.stop()
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
        dismissWindow(id: MacAppModel.playerWindowID)
    }

    private func startPlayback(for activity: StrimrWatchActivity) async {
        playerController.stop()
        loadedURL = nil
        audioTracks = []
        subtitleTracks = []
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        viewModel = PlayerViewModel(
            playQueue: viewModel.playQueue,
            ratingKey: activity.ratingKey,
            context: context,
            shouldResumeFromOffset: false,
        )
        await viewModel.load()
        startPlaybackIfNeeded(viewModel.playbackURL)
    }

    private func handlePointerMovement(_ phase: HoverPhase) {
        switch phase {
        case .active:
            isPointerInsidePlayer = true
            showControls(temporarily: true)
        case .ended:
            isPointerInsidePlayer = false
            restoreCursor()
        }
    }

    private func toggleControlsVisibility() {
        if controlsVisible {
            hideControls(force: true)
        } else {
            showControls(temporarily: true)
        }
    }

    private func showControls(temporarily: Bool) {
        hideControlsWorkItem?.cancel()
        restoreCursor()
        withAnimation(.easeInOut) {
            controlsVisible = true
        }

        if temporarily {
            scheduleControlsHide()
        }
    }

    private func scheduleControlsHide() {
        hideControlsWorkItem?.cancel()
        guard !playerController.isPaused, !isScrubbing, !isShowingError else { return }

        let workItem = DispatchWorkItem {
            hideControls(force: false)
        }
        hideControlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + controlsHideDelay, execute: workItem)
    }

    private func hideControls(force: Bool) {
        hideControlsWorkItem?.cancel()
        guard force || (!playerController.isPaused && !isScrubbing && !isShowingError) else { return }

        withAnimation(.easeInOut) {
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
}
