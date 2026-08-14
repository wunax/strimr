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
            .id(presentation.id)
        } else {
            ContentUnavailableView("player.window.title", systemImage: "play.rectangle")
        }
    }

    private func playerViewModel(
        for presentation: AppModel.PlayerPresentation
    ) -> PlayerViewModel? {
        if let media = presentation.localMedia, let url = presentation.localPlaybackURL {
            return PlayerViewModel(localMedia: media, localPlaybackURL: url)
        }
        if let queue = presentation.mediaQueue, let services = presentation.mediaServices {
            return PlayerViewModel(
                queue: queue,
                services: services,
                shouldResumeFromOffset: presentation.shouldResumeFromOffset
            )
        }
        return nil
    }
}

struct PlayerView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(AppModel.self) private var appModel
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator

    @State private var viewModel: PlayerViewModel
    @State private var playerController = PlayerController()
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var automaticSkipFeedbackWorkItem: DispatchWorkItem?
    @State private var automaticSkipFeedbackMessage: String?
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
    @State private var isShowingSubtitleSearch = false
    @State private var subtitleSearchErrorMessage = ""
    @State private var isShowingSubtitleSearchError = false
    @State private var isShowingSharePlayExitPrompt = false
    @State private var participatesInSharePlay = false
    @State private var isShowingChapterPopover = false
    @State private var isRecoveringServerAccess = false
    @State private var isShowingServerRecoveryAlert = false
    @State private var serverRecoveryError: MediaServerAccessRecoveryError?
    @State private var lastReloadedServerAccessGeneration = -1
    @State private var shouldResumeAfterMediaLoad = false
    @State private var shouldPauseAfterMediaLoad = false

    private let presentationID: UUID
    private let controlsHideDelay: TimeInterval = 3

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
                currentTime: playerController.sourcePosition,
                maxCueDuration: playerController.subtitleMaxCueDuration,
                appearance: settingsManager.playback.subtitleAppearance,
                bottomPadding: controlsVisible ? 96 : 48,
                videoSize: playerController.sourceVideoSize,
                assRenderer: playerController.assRenderer,
                assReloadSignal: playerController.assReloadSignal,
                activeSubtitleCodec: playerController.activeSubtitleCodec,
            )
            .ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleControlsVisibility() }

            if viewModel.isLoading || viewModel.isBuffering || isRecoveringServerAccess {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if controlsVisible {
                controls
                    .transition(.opacity)
            }

            if let automaticSkipFeedbackMessage {
                AutomaticSkipFeedbackView(message: automaticSkipFeedbackMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, controlsVisible ? 110 : 32)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(false)
            }

            keyboardCommands
        }
        .background(.black)
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
                    await viewModel.load()
                    startPlaybackIfNeeded(viewModel.playbackURL)
                }
                .onDisappear {
                    hideControlsWorkItem?.cancel()
                    automaticSkipFeedbackWorkItem?.cancel()
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
                    handleAutomaticMarkerSkipIfNeeded()
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
                },
        )

        return presentationObservers
            .sheet(isPresented: $isShowingSubtitleSearch) {
                if let services = viewModel.subtitleSearchServices {
                    SubtitleSearchView(
                        itemID: viewModel.currentRatingKey,
                        titlePlaceholder: viewModel.subtitleSearchTitlePlaceholder,
                        services: services,
                        onAttached: handleAttachedSubtitle(_:)
                    )
                    .frame(minWidth: 560, minHeight: 640)
                }
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
            .alert("subtitles.search.activation.error", isPresented: $isShowingSubtitleSearchError) {
                Button("common.actions.done", role: .cancel) {}
            } message: {
                Text(subtitleSearchErrorMessage)
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
                            playerController.seek(to: marker.endTime)
                        }
                        .buttonStyle(.borderedProminent)
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
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                HStack(spacing: 10) {
                    Text(formatTime(scrubPosition))
                        .font(.caption.monospacedDigit())
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
                                withAnimation(.easeInOut(duration: 0.15)) {
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
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .fixedSize()
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

                    if playerController.showsPictureInPictureControl {
                        Button {
                            playerController.startPictureInPicture()
                        } label: {
                            Image(systemName: "pip.enter")
                        }
                        .disabled(
                            !playerController.isPictureInPictureAvailable
                                || playerController.isPictureInPictureActive
                                || playerController.isPictureInPictureTransitioning,
                        )
                        .accessibilityLabel(String(localized: "player.controls.pictureInPicture"))
                    }

                    audioMenu
                    subtitleMenu
                    speedMenu

                    if viewModel.hasNavigableChapters {
                        chapterButton
                    }
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
                        Task { await viewModel.persistStreamSelection(for: track) }
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
                playerController.selectSubtitleTrack(
                    id: nil,
                    styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                )
                Task { await viewModel.persistSubtitleStreamSelection(for: nil) }
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
                    playerController.selectSubtitleTrack(
                        id: track.id,
                        styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                    )
                    Task { await viewModel.persistSubtitleStreamSelection(for: track) }
                } label: {
                    if selectedSubtitleTrackID == track.id {
                        Label(track.displayName, systemImage: "checkmark")
                    } else {
                        Text(track.displayName)
                    }
                }
            }
            if viewModel.canSearchSubtitles {
                Divider()
                Button {
                    isShowingSubtitleSearch = true
                } label: {
                    Label("subtitles.search.action", systemImage: "magnifyingglass")
                }
                .tint(.secondary)
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

    private func handleAttachedSubtitle(_: RemoteSubtitleResult) async {
        do {
            let subtitle = try await viewModel.refreshMetadataAfterSubtitleAttachment()
            let id = try playerController.registerExternalSubtitleIfNeeded(
                subtitle,
                styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
            )
            selectedSubtitleTrackID = id
            let tracks = playerController.trackList()
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
            Label("player.chapters.title", systemImage: "list.bullet.rectangle")
        }
        .popover(isPresented: $isShowingChapterPopover, arrowEdge: .bottom) {
            PlayerChapterPopover(
                chapters: viewModel.chapters,
                currentPosition: viewModel.position,
                imageURL: { chapter in
                    viewModel.chapterImageURL(for: chapter, width: 320, height: 180)
                },
                onSelect: selectChapter(_:),
            )
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
        playerController.onPictureInPictureRestoreRequested = {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: AppModel.playerWindowID)
        }
        playerController.onMediaLoaded = {
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

                if let preferredSubtitle = viewModel.preferredSubtitleStreamID,
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
            httpHeaders: viewModel.playbackHTTPHeaders,
            startPosition: startPosition,
            preferredAudioTrackID: viewModel.preferredAudioStreamFFIndex,
            losslessAudio: settingsManager.playback.losslessAudio,
            styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
            mediaIdentifier: viewModel.media?.id ?? url.lastPathComponent,
            providerStreamIDsByFFIndex: viewModel.providerStreamIDsByFFIndex(),
            externalSubtitles: viewModel.externalSubtitleTracks(),
            scrubThumbnailSource: viewModel.scrubThumbnailSource,
            showsScrubThumbnailPreviews: settingsManager.playback.showScrubThumbnailPreviews,
            generatesMissingScrubThumbnailPreviews:
            settingsManager.playback.generateMissingScrubThumbnailPreviews,
            autoplay: !isSharePlayPlayback,
        )
        playerController.setPlaybackRate(playbackRate)
    }

    private func handleAutomaticMarkerSkipIfNeeded() {
        guard !isScrubbing else { return }
        guard !(participatesInSharePlay && sharePlayCoordinator.isInSession) else { return }
        guard let marker = viewModel.automaticSkipMarker(
            autoSkipIntros: settingsManager.playback.autoSkipIntros,
            autoSkipCredits: settingsManager.playback.autoSkipCredits,
        ) else {
            return
        }

        playerController.seek(to: marker.endTime)
        viewModel.position = marker.endTime
        scrubPosition = marker.endTime
        showAutomaticSkipFeedback(for: marker)
    }

    private func showAutomaticSkipFeedback(for marker: SkipSegment) {
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

    private func handlePlaybackEnded() async {
        await viewModel.markPlaybackFinished()
        let isSharePlayPlayback = participatesInSharePlay && sharePlayCoordinator.isInSession
        guard isSharePlayPlayback || settingsManager.playback.autoPlayNextEpisode else {
            playerController.pause()
            return
        }

        if viewModel.usesCommonPlaybackQueue {
            guard let nextViewModel = viewModel.nextCommonPlayerViewModel() else {
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
                styledASSSubtitles: settingsManager.playback.styledASSSubtitles,
                mediaIdentifier: viewModel.media?.id ?? url.lastPathComponent,
                providerStreamIDsByFFIndex: viewModel.providerStreamIDsByFFIndex(),
                externalSubtitles: viewModel.externalSubtitleTracks(),
                scrubThumbnailSource: viewModel.scrubThumbnailSource,
                showsScrubThumbnailPreviews: settingsManager.playback.showScrubThumbnailPreviews,
                generatesMissingScrubThumbnailPreviews:
                settingsManager.playback.generateMissingScrubThumbnailPreviews,
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
        if let error {
            await sessionManager.handleTerminalServerAccessFailure(error)
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
        guard
            !playerController.isPaused,
            !isScrubbing,
            !isShowingError,
            !isShowingChapterPopover
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
            )
        else {
            return
        }

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

    private func selectChapter(_ chapter: MediaChapter) {
        playerController.seek(to: chapter.startTime)
        scrubPosition = chapter.startTime
        viewModel.handlePlaybackPosition(chapter.startTime, isScrubbing: false)
        isShowingChapterPopover = false
    }
}
