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
    let onShowDownloadOptions: () -> Void
    let onShowShowDownloadSheet: () -> Void
    let onShowFileInfo: () -> Void
    let onStartSharePlay: () -> Void
    @State private var mediaToAddToPlaylist: MediaItem?

    var body: some View {
        playButton
        if isServerUnreachable, downloadedPlayback == nil {
            if viewModel.reachableCopyReplacingUnavailableServer != nil {
                ReachableCopyPlayButton(viewModel: viewModel, presenter: coordinator)
            } else {
                Label("offline.detail.notAvailable", systemImage: "wifi.slash")
                    .font(.facts)
                    .foregroundStyle(.secondary)
            }
        }
        if [.show, .season].contains(viewModel.media.type) {
            DownloadedEpisodesLabel(media: viewModel.media.mediaItem)
        }
        secondaryButtonsRow
    }

    private var secondaryButtonsRow: some View {
        HStack(alignment: .top, spacing: 20) {
            watchToggleButton

            if viewModel.shouldShowFavoriteButton {
                favoriteButton
            }

            if mediaServices.capabilities.downloads {
                downloadButton
            }

            moreButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var moreButton: some View {
        Menu {
            if canPlayFromStart {
                Button(action: handlePlayFromStart) {
                    Label("media.detail.playFromStart", systemImage: "arrow.counterclockwise")
                }
            }

            // Streaming stays the default online (the download may be lower quality); this plays the local copy.
            if !isServerUnreachable, let request = downloadedPlayback {
                Button {
                    coordinator.showLocalPlayer(request)
                } label: {
                    Label("offline.detail.playDownloaded", systemImage: "arrow.down.circle")
                }
            }

            if !isServerUnreachable {
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

                if AddToPlaylistViewModel.canAdd(viewModel.media.mediaItem) {
                    Button {
                        mediaToAddToPlaylist = viewModel.media.mediaItem
                    } label: {
                        Label("playlist.add.menuTitle", systemImage: "text.badge.plus")
                    }
                }

                if viewModel.canShowFileInfo {
                    Divider()
                    Button(action: onShowFileInfo) {
                        Label("media.fileInfo.title", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }

            if !viewModel.listsCopiesWithVersions {
                MediaCopiesMenuItems(viewModel: viewModel)
            }
        } label: {
            DetailRoundActionLabel(
                title: "common.actions.more",
                systemImage: "ellipsis",
                isActive: false,
                isLoading: false,
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("common.actions.more"))
        .addToPlaylistPresentation(media: $mediaToAddToPlaylist, services: mediaServices)
    }

    private var canPlayFromStart: Bool {
        viewModel.shouldShowPlayFromStartButton && (!isServerUnreachable || downloadedPlayback != nil)
    }

    private var isPlayDisabled: Bool {
        viewModel.primaryActionRatingKey == nil || (isServerUnreachable && downloadedPlayback == nil)
    }

    private var isServerUnreachable: Bool {
        offlineCoordinator.isUnreachable(mediaServices.identity)
    }

    private var downloadedPlayback: LocalPlaybackRequest? {
        downloadManager.localPlaybackRequest(forDetail: viewModel)
    }

    private var playButton: some View {
        Button(action: handlePlay) {
            HStack(spacing: 10) {
                PlayProgressIcon(progress: viewModel.primaryActionProgress)
                Text(viewModel.primaryActionCompactTitle)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let remainingTime = viewModel.primaryActionRemainingTime {
                    Text(verbatim: "· \(remainingTime)")
                        .foregroundStyle(isPlayDisabled ? Color.secondary : Color.black.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .actionButtonStyle(.primary)
        .disabled(isPlayDisabled)
    }

    private var watchToggleButton: some View {
        Button {
            Task {
                if viewModel.shouldShowBothWatchActions {
                    await viewModel.markWatched()
                } else {
                    await viewModel.toggleWatchStatus()
                }
            }
        } label: {
            DetailRoundActionLabel(
                title: "media.detail.action.watched",
                systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle",
                isActive: isWatched,
                isLoading: viewModel.isUpdatingWatchStatus,
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus || isServerUnreachable)
        .accessibilityLabel(Text(
            viewModel.shouldShowBothWatchActions
                ? String(localized: "media.detail.watchAction.markWatched")
                : viewModel.watchActionTitle,
        ))
    }

    private var isWatched: Bool {
        viewModel.isWatched(viewModel.media.mediaItem)
    }

    private var favoriteButton: some View {
        Button {
            Task { await viewModel.toggleFavoriteStatus() }
        } label: {
            DetailRoundActionLabel(
                title: "media.detail.action.favorite",
                systemImage: viewModel.isFavorite ? "star.fill" : "star",
                isActive: viewModel.isFavorite,
                isLoading: viewModel.isLoadingFavoriteStatus || viewModel.isUpdatingFavoriteStatus,
            )
        }
        .buttonStyle(.plain)
        .disabled(
            viewModel.isLoading
                || viewModel.isLoadingFavoriteStatus
                || viewModel.isUpdatingFavoriteStatus
                || isServerUnreachable,
        )
        .accessibilityLabel(Text(viewModel.favoriteActionTitle))
    }

    private var downloadButton: some View {
        Button {
            handleDownloadTap()
        } label: {
            DetailRoundActionLabel(
                title: "downloads.action",
                systemImage: downloadIconName,
                isActive: downloadStatus == .completed,
                isLoading: isDownloadInProgress,
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading || isServerUnreachable)
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
