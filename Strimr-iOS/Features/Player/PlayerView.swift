import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlexAPIContext.self) private var context
    @Environment(SettingsManager.self) private var settingsManager
    @State var viewModel: PlayerViewModel
    let activePlayer: PlaybackPlayer
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
    @State private var appliedPreferredAudio = false
    @State private var appliedPreferredSubtitle = false
    @State private var appliedResumeOffset = false
    @State private var timelinePosition = 0.0

    private let controlsHideDelay: TimeInterval = 3.0
    private var seekBackwardInterval: Double {
        Double(settingsManager.playback.seekBackwardSeconds)
    }

    private var seekForwardInterval: Double {
        Double(settingsManager.playback.seekForwardSeconds)
    }

    init(viewModel: PlayerViewModel, initialPlayer: PlaybackPlayer) {
        _viewModel = State(initialValue: viewModel)
        activePlayer = initialPlayer
        _playerCoordinator = State(initialValue: PlayerFactory.makeCoordinator(for: initialPlayer))
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
                        isScrubbing: isScrubbing
                    )

                    if propertyName == .videoParamsSigPeak {
                        let supportsHdr = (data as? Double ?? 1.0) > 1.0
                        supportsHDR = supportsHdr
                    }
                },
                onPlaybackEnded: {
                    handlePlaybackEnded()
                }
            )
            .onAppear {
                showControls(temporarily: true)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                controlsVisible ? hideControls() : showControls(temporarily: true)
            }

            if bindableViewModel.isBuffering {
                bufferingOverlay
            }

            if controlsVisible {
                PlayerControlsView(
                    media: bindableViewModel.media,
                    isPaused: bindableViewModel.isPaused,
                    isBuffering: bindableViewModel.isBuffering,
                    supportsHDR: supportsHDR,
                    position: timelineBinding,
                    duration: bindableViewModel.duration,
                    bufferedAhead: bindableViewModel.bufferedAhead,
                    bufferBasePosition: bindableViewModel.position,
                    isScrubbing: isScrubbing,
                    onDismiss: dismissPlayer,
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
                    }
                )
                .transition(.opacity)
            }

            if !controlsVisible, let activeMarker, let skipTitle {
                skipOverlay(marker: activeMarker, title: skipTitle)
            }
        }
        .statusBarHidden()
        .onAppear {
            showControls(temporarily: true)
        }
        .onDisappear {
            viewModel.handleStop()
            hideControlsWorkItem?.cancel()
            playerCoordinator.destruct()
        }
        .task {
            await bindableViewModel.load()
        }
        .onChange(of: bindableViewModel.playbackURL) { _, newURL in
            guard let url = newURL else { return }
            appliedPreferredAudio = false
            appliedPreferredSubtitle = false
            selectedAudioTrackID = nil
            selectedSubtitleTrackID = nil
            appliedResumeOffset = false
            playerCoordinator.play(url)
            showControls(temporarily: true)
            refreshTracks()
            applyResumeOffsetIfNeeded()
        }
        .onChange(of: bindableViewModel.position) { _, newValue in
            guard !isScrubbing else { return }
            timelinePosition = newValue
        }
        .sheet(isPresented: $showingSettings) {
            PlaybackSettingsView(
                audioTracks: settingsAudioTracks,
                subtitleTracks: settingsSubtitleTracks,
                selectedAudioTrackID: selectedAudioTrackID,
                selectedSubtitleTrackID: selectedSubtitleTrackID,
                onSelectAudio: selectAudioTrack(_:),
                onSelectSubtitle: selectSubtitleTrack(_:),
                onClose: { showingSettings = false }
            )
            .presentationDetents([.medium])
            .presentationBackground(.ultraThinMaterial)
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
            set: { timelinePosition = $0 }
        )
    }

    private func togglePlayPause() {
        playerCoordinator.togglePlayback()
        showControls(temporarily: true)
    }

    private func showSettings() {
        refreshTracks()
        showingSettings = true
        hideControlsWorkItem?.cancel()
    }

    private func refreshTracks() {
        Task {
            // Waits for the player to hydrate the tracks
            try await Task.sleep(for: .milliseconds(150))
            let tracks = playerCoordinator.trackList()

            let audio = tracks.filter { $0.type == .audio }
            let subtitles = tracks.filter { $0.type == .subtitle }

            await MainActor.run {
                audioTracks = audio
                subtitleTracks = subtitles

                settingsAudioTracks = audio.map {
                    PlaybackSettingsTrack(
                        track: $0,
                        plexStream: viewModel.plexStream(forFFIndex: $0.ffIndex)
                    )
                }

                settingsSubtitleTracks = subtitles.map {
                    PlaybackSettingsTrack(
                        track: $0,
                        plexStream: viewModel.plexStream(forFFIndex: $0.ffIndex)
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

    private func jump(by seconds: Double) {
        playerCoordinator.seek(by: seconds)
        showControls(temporarily: true)
    }

    private func applyResumeOffsetIfNeeded() {
        guard !appliedResumeOffset, let offset = viewModel.resumePosition, offset > 0 else { return }
        appliedResumeOffset = true

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            playerCoordinator.seek(to: offset)
        }
    }

    private func dismissPlayer() {
        hideControlsWorkItem?.cancel()
        dismiss()
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
        }
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
    }

    private func skipOverlay(marker: PlexMarker, title: String) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                SkipMarkerButton(title: title) {
                    skipMarker(to: marker)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func handlePlaybackEnded() {
        guard let media = viewModel.media else {
            dismissPlayer()
            return
        }

        switch media.type {
        case .movie:
            dismissPlayer()
        case .episode:
            Task {
                await handleEpisodeCompletion(for: media)
            }
        default:
            dismissPlayer()
        }
    }

    private func handleEpisodeCompletion(for media: MediaItem) async {
        guard settingsManager.playback.autoPlayNextEpisode else {
            await MainActor.run {
                dismissPlayer()
            }
            return
        }

        await viewModel.markPlaybackFinished()

        guard
            let grandparentRatingKey = media.grandparentRatingKey,
            let nextEpisode = await viewModel.fetchOnDeckEpisode(grandparentRatingKey: grandparentRatingKey)
        else {
            await MainActor.run {
                dismissPlayer()
            }
            return
        }

        await startPlayback(of: nextEpisode)
    }

    private func startPlayback(of episode: PlexItem) async {
        await MainActor.run {
            viewModel = PlayerViewModel(
                ratingKey: episode.ratingKey,
                context: context
            )
        }

        await viewModel.load()
    }
}

#Preview {
    let context = PlexAPIContext()
    let viewModel = PlayerViewModel(ratingKey: "demo", context: context)
    return PlayerView(viewModel: viewModel, initialPlayer: .mpv)
        .environment(context)
}
