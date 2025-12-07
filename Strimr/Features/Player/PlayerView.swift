import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: PlayerViewModel
    @State private var coordinator = MPVPlayerView.Coordinator()
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var isScrubbing = false
    @State private var supportsHDR = false
    @State private var showingSettings = false
    @State private var audioTracks: [MPVTrack] = []
    @State private var subtitleTracks: [MPVTrack] = []
    @State private var selectedAudioTrackID: Int?
    @State private var selectedSubtitleTrackID: Int?
    @State private var appliedPreferredAudio = false
    @State private var appliedPreferredSubtitle = false
    @State private var appliedResumeOffset = false

    private let controlsHideDelay: TimeInterval = 3.0
    private let seekInterval: Double = 10

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ZStack {
            Color.black.ignoresSafeArea()

            MPVPlayerView(coordinator: coordinator)
                .onPropertyChange { player, propertyName, data in
                    bindableViewModel.handlePropertyChange(
                        name: propertyName,
                        data: data,
                        isScrubbing: isScrubbing
                    )

                    if propertyName == MPVProperty.videoParamsSigPeak {
                        let supportsHdr = (data as? Double ?? 1.0) > 1.0
                        supportsHDR = supportsHdr
                        player.hdrEnabled = supportsHdr
                    }
                }
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
                    position: positionBinding(for: bindableViewModel),
                    duration: bindableViewModel.duration,
                    bufferedAhead: bindableViewModel.bufferedAhead,
                    onDismiss: dismissPlayer,
                    onShowSettings: showSettings,
                    onSeekBackward: { jump(by: -seekInterval) },
                    onPlayPause: togglePlayPause,
                    onSeekForward: { jump(by: seekInterval) },
                    onScrubbingChanged: handleScrubbing(editing:)
                )
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .onAppear {
            showControls(temporarily: true)
        }
        .onDisappear {
            viewModel.handleStop()
            hideControlsWorkItem?.cancel()
            coordinator.player?.destruct()
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
            coordinator.play(url)
            showControls(temporarily: true)
            refreshTracks()
            applyResumeOffsetIfNeeded()
        }
        .sheet(isPresented: $showingSettings) {
            PlaybackSettingsView(
                audioTracks: audioTracks,
                subtitleTracks: subtitleTracks,
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
                
                Text("Buffering")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.bottom, 20)
    }

    private func positionBinding(for viewModel: PlayerViewModel) -> Binding<Double> {
        Binding(
            get: { viewModel.position },
            set: { viewModel.position = $0 }
        )
    }

    private func togglePlayPause() {
        coordinator.togglePlayback()
        showControls(temporarily: true)
    }

    private func showSettings() {
        refreshTracks()
        showingSettings = true
        hideControlsWorkItem?.cancel()
    }

    private func refreshTracks() {
        Task {
            // Waits for MPV player to hydrate the tracks
            try await Task.sleep(for: .milliseconds(150))
            let tracks = coordinator.trackList()

            let audio = tracks.filter { $0.type == .audio }
            let subtitles = tracks.filter { $0.type == .subtitle }

            await MainActor.run {
                audioTracks = audio
                subtitleTracks = subtitles

                applyPreferredTracksIfNeeded(audioTracks: audio, subtitleTracks: subtitles)

                if selectedAudioTrackID == nil,
                   let activeAudio = audio.first(where: { $0.isSelected })?.id ?? audioTracks.first?.id {
                    selectedAudioTrackID = activeAudio
                }

                if selectedSubtitleTrackID == nil,
                   let activeSubtitle = subtitles.first(where: { $0.isSelected })?.id {
                    selectedSubtitleTrackID = activeSubtitle
                }
            }
        }
    }

    private func selectAudioTrack(_ id: Int?) {
        selectedAudioTrackID = id
        coordinator.selectAudioTrack(id: id)

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
        coordinator.selectSubtitleTrack(id: id)

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
        coordinator.seek(by: seconds)
        showControls(temporarily: true)
    }

    private func applyResumeOffsetIfNeeded() {
        guard !appliedResumeOffset, let offset = viewModel.resumePosition, offset > 0 else { return }
        appliedResumeOffset = true

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            coordinator.seek(to: offset)
        }
    }

    private func dismissPlayer() {
        hideControlsWorkItem?.cancel()
        dismiss()
    }

    private func handleScrubbing(editing: Bool) {
        isScrubbing = editing

        if editing {
            hideControlsWorkItem?.cancel()
            withAnimation(.easeInOut) {
                controlsVisible = true
            }
        } else {
            coordinator.seek(to: viewModel.position)
            scheduleControlsHide()
        }
    }

    private func showControls(temporarily: Bool) {
        withAnimation(.easeInOut) {
            controlsVisible = true
        }

        if temporarily && !isScrubbing {
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

    private func applyPreferredTracksIfNeeded(audioTracks: [MPVTrack], subtitleTracks: [MPVTrack]) {
        if !appliedPreferredAudio,
           let preferredAudioIndex = viewModel.preferredAudioStreamFFIndex,
           let track = audioTracks.first(where: { $0.ffIndex == preferredAudioIndex }) {
            selectedAudioTrackID = track.id
            coordinator.selectAudioTrack(id: track.id)
            appliedPreferredAudio = true
        }

        if !appliedPreferredSubtitle,
           let preferredSubtitleIndex = viewModel.preferredSubtitleStreamFFIndex,
           let track = subtitleTracks.first(where: { $0.ffIndex == preferredSubtitleIndex }) {
            
            debugPrint(preferredSubtitleIndex)
            
            selectedSubtitleTrackID = track.id
            coordinator.selectSubtitleTrack(id: track.id)
            appliedPreferredSubtitle = true
        }
    }
}

#Preview {
    let context = PlexAPIContext()
    let viewModel = PlayerViewModel(ratingKey: "demo", context: context)
    return PlayerView(viewModel: viewModel)
        .environment(context)
}
