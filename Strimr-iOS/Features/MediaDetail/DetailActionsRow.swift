import SwiftUI

/// Play buttons and the row of secondary actions under the title.
struct DetailActionsRow: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(MediaServices.self) private var mediaServices
    @Bindable var viewModel: MediaDetailViewModel
    let isStartingSharePlay: Bool
    let onPlay: (String, MediaKind) -> Void
    let onPlayFromStart: (String, MediaKind) -> Void
    let onShuffle: (String, MediaKind) -> Void
    let onSearchSubtitles: () -> Void
    let onShowDownloadOptions: () -> Void
    let onShowShowDownloadSheet: () -> Void
    let onShowFileInfo: () -> Void
    let onStartSharePlay: () -> Void

    var body: some View {
        playButtonsRow
        if isServerUnreachable, downloadedPlayback == nil {
            if viewModel.reachableCopyReplacingUnavailableServer != nil {
                ReachableCopyPlayButton(viewModel: viewModel, presenter: coordinator)
            } else {
                Label("offline.detail.notAvailable", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if [.show, .season].contains(viewModel.media.type) {
            DownloadedEpisodesLabel(media: viewModel.media.mediaItem)
        }
        secondaryButtonsRow
    }

    private var secondaryButtonsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            watchToggleButton

            DetailPlaybackCard(
                viewModel: viewModel,
                isServerUnreachable: isServerUnreachable,
                onSearchSubtitles: onSearchSubtitles,
            )

            if mediaServices.capabilities.downloads {
                downloadButton
            }
            moreButton
                .disabled(isServerUnreachable)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var moreButton: some View {
        VStack(spacing: 2) {
            Menu {
                if viewModel.shouldShowWatchlistButton {
                    Button {
                        Task { await viewModel.toggleWatchlistStatus() }
                    } label: {
                        Label(viewModel.watchlistActionTitle, systemImage: viewModel.watchlistActionIcon)
                    }
                    .disabled(
                        viewModel.isLoading
                            || viewModel.isLoadingWatchlistStatus
                            || viewModel.isUpdatingWatchlistStatus,
                    )
                }

                if viewModel.shouldShowFavoriteButton {
                    Button {
                        Task { await viewModel.toggleFavoriteStatus() }
                    } label: {
                        Label(viewModel.favoriteActionTitle, systemImage: viewModel.favoriteActionIcon)
                    }
                    .disabled(
                        viewModel.isLoading
                            || viewModel.isLoadingFavoriteStatus
                            || viewModel.isUpdatingFavoriteStatus,
                    )
                }

                if viewModel.shouldShowBothWatchActions {
                    Button {
                        Task { await viewModel.markUnwatched() }
                    } label: {
                        Label(
                            "media.detail.watchAction.markUnwatched",
                            systemImage: "checkmark.circle.fill",
                        )
                    }
                    .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus)
                }

                Button(action: handleShuffle) {
                    Label("common.actions.shuffle", systemImage: "shuffle")
                }

                if viewModel.primaryActionRatingKey != nil {
                    Button(action: onStartSharePlay) {
                        Label("sharePlay.action", systemImage: "shareplay")
                    }
                    .disabled(isStartingSharePlay)
                }

                if viewModel.canShowFileInfo {
                    Divider()
                    Button(action: onShowFileInfo) {
                        Label("media.fileInfo.title", systemImage: "doc.text.magnifyingglass")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.brandSecondary)
            .frame(width: 48, height: 44)

            Text("common.actions.more")
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(maxWidth: 48)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .accessibilityLabel(Text("common.actions.more"))
    }

    private var playButtonsRow: some View {
        HStack(spacing: 12) {
            playButton

            if viewModel.shouldShowPlayFromStartButton, !isServerUnreachable || downloadedPlayback != nil {
                playFromStartButton
            }

            if !isServerUnreachable, downloadedPlayback != nil {
                playDownloadedButton
            }
        }
    }

    /// The disabled prominent background is dark, so the dark brand foreground would hide the label.
    private var isPlayDisabled: Bool {
        viewModel.primaryActionRatingKey == nil || (isServerUnreachable && downloadedPlayback == nil)
    }

    private var isServerUnreachable: Bool {
        offlineCoordinator.isUnreachable(mediaServices.identity)
    }

    private var downloadedPlayback: LocalPlaybackRequest? {
        downloadManager.localPlaybackRequest(forDetail: viewModel)
    }

    /// Streaming stays the default online (the download may be lower quality); this plays the local copy instead.
    private var playDownloadedButton: some View {
        Button {
            if let request = downloadedPlayback {
                coordinator.showLocalPlayer(request)
            }
        } label: {
            Image(systemName: "arrow.down.circle")
                .font(.title2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.brandSecondary)
        .accessibilityLabel(Text("offline.detail.playDownloaded"))
    }

    private var playButton: some View {
        Button(action: handlePlay) {
            HStack(spacing: 12) {
                PlayProgressIcon(progress: viewModel.primaryActionProgress)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.primaryActionTitle)
                        .fontWeight(.semibold)
                    if let detail = viewModel.primaryActionDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brandSecondary)
        .foregroundStyle(isPlayDisabled ? Color.secondary : Color.brandSecondaryForeground)
        .disabled(isPlayDisabled)
    }

    private var playFromStartButton: some View {
        Button(action: handlePlayFromStart) {
            Image(systemName: "arrow.counterclockwise")
                .font(.title2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.brandSecondary)
        .accessibilityLabel(Text("media.detail.playFromStart"))
    }

    private var watchToggleButton: some View {
        VStack(spacing: 2) {
            Button {
                Task {
                    if viewModel.shouldShowBothWatchActions {
                        await viewModel.markWatched()
                    } else {
                        await viewModel.toggleWatchStatus()
                    }
                }
            } label: {
                if viewModel.isUpdatingWatchStatus {
                    ProgressView()
                        .tint(.brandSecondaryForeground)
                } else if viewModel.shouldShowBothWatchActions {
                    Image(systemName: "checkmark.circle")
                        .font(.headline.weight(.semibold))
                } else {
                    Image(systemName: viewModel.watchActionIcon)
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(width: 48, height: 44)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.brandSecondary)
            .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus || isServerUnreachable)

            Text(
                viewModel.shouldShowBothWatchActions
                    ? String(localized: "media.detail.watchAction.markWatched")
                    : viewModel.watchActionTitle,
            )
            .font(.caption2)
            .foregroundStyle(.primary)
            .frame(maxWidth: 48)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
    }

    private var downloadButton: some View {
        VStack(spacing: 2) {
            Button {
                handleDownloadTap()
            } label: {
                if isDownloadInProgress {
                    ProgressView()
                        .tint(.brandSecondaryForeground)
                } else {
                    Image(systemName: downloadIconName)
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(width: 48, height: 44)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.brandSecondary)
            .disabled(viewModel.isLoading || isServerUnreachable)

            Text("downloads.action")
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(maxWidth: 52)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private func handlePlay() {
        if isServerUnreachable {
            if let request = downloadManager.localPlaybackRequest(
                forDetail: viewModel,
                resumes: !viewModel.shouldPlayPrimaryActionFromStart,
            ) {
                coordinator.showLocalPlayer(request)
            }
            return
        }
        Task {
            guard
                let ratingKey = await viewModel.playbackRatingKey(),
                let playbackType = viewModel.primaryActionType
            else { return }

            if viewModel.shouldPlayPrimaryActionFromStart {
                onPlayFromStart(ratingKey, playbackType)
            } else {
                onPlay(ratingKey, playbackType)
            }
        }
    }

    private func handlePlayFromStart() {
        if isServerUnreachable {
            if let request = downloadManager.localPlaybackRequest(forDetail: viewModel, resumes: false) {
                coordinator.showLocalPlayer(request)
            }
            return
        }
        Task {
            guard
                let ratingKey = await viewModel.playbackRatingKey(),
                let playbackType = viewModel.primaryActionType
            else { return }
            onPlayFromStart(ratingKey, playbackType)
        }
    }

    private func handleShuffle() {
        onShuffle(viewModel.media.id, viewModel.media.mediaKind)
    }

    private func handleDownloadTap() {
        switch viewModel.media.mediaKind {
        case .series:
            onShowShowDownloadSheet()
        case .season:
            onShowDownloadOptions()
        case .movie, .episode:
            onShowDownloadOptions()
        case .clip:
            break
        case .collection, .playlist, .folder, .unknown:
            break
        }
    }

    private var downloadStatus: DownloadStatus? {
        downloadManager.status(for: viewModel.media.identity)
    }

    private var isDownloadInProgress: Bool {
        downloadStatus == .queued || downloadStatus == .preparing || downloadStatus == .downloading
    }

    private var downloadIconName: String {
        switch downloadStatus {
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.circle"
        case .queued, .preparing, .downloading:
            "arrow.down.circle.fill"
        case nil:
            "arrow.down.circle"
        }
    }
}

private struct PlayProgressIcon: View {
    let progress: Double?

    var body: some View {
        ZStack {
            if let progress {
                Circle()
                    .stroke(Color.brandSecondaryForeground.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.brandSecondaryForeground,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round),
                    )
                    .rotationEffect(.degrees(-90))
            }

            Image(systemName: "play.fill")
                .font(.title3.weight(.semibold))
        }
        .frame(width: 30, height: 30)
    }
}
