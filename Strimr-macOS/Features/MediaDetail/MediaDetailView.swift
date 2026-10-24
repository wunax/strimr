import AppKit
import GroupActivities
import SwiftUI

struct MediaDetailView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(MediaServices.self) private var mediaServices
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @Environment(AppModel.self) private var appModel
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @State private var viewModel: MediaDetailViewModel
    @State private var isShowingShowDownloadSheet = false
    @State private var isShowingDownloadOptions = false
    @State private var sharePlaySharingRequest: SharePlaySharingRequest?
    @State private var isShowingSubtitleSearch = false
    @State private var isShowingFileInfo = false
    @State private var isMoreMenuHovered = false
    @State private var mediaToAddToPlaylist: MediaItem?
    let onSelectMedia: (MediaItem) -> Void
    let onSelectParentSeries: (PlayableMediaItem) -> Void
    let onSelectPerson: (Person) -> Void
    let onPlay: (String, MediaKind, Bool, Bool) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onSelectMedia: @escaping (MediaItem) -> Void,
        onSelectParentSeries: @escaping (PlayableMediaItem) -> Void,
        onSelectPerson: @escaping (Person) -> Void = { _ in },
        onPlay: @escaping (String, MediaKind, Bool, Bool) -> Void,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onSelectParentSeries = onSelectParentSeries
        self.onSelectPerson = onSelectPerson
        self.onPlay = onPlay
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            MediaBackdropGradient(colors: viewModel.backdropGradient)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    hero
                    details

                    if [.show, .season].contains(viewModel.media.type) {
                        episodesSection
                    }

                    CastSection(
                        viewModel: viewModel,
                        onSelectPerson: onSelectPerson,
                    )
                    ExtrasSection(viewModel: viewModel) { extra in
                        onPlay(extra.id, .clip, false, true)
                    }
                    RelatedHubsSection(viewModel: viewModel) { media in
                        if case let .playable(item) = media {
                            onSelectMedia(item)
                        }
                    }

                    DetailFactsSection(viewModel: viewModel)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(viewModel.detailPrimaryLabel)
        .task { await viewModel.loadDetails() }
        .themeMusic(path: viewModel.media.mediaItem.themePath)
        .sheet(isPresented: $isShowingShowDownloadSheet) {
            ShowDownloadSelectionSheet(
                viewModel: viewModel,
                services: mediaServices,
                defaultQuality: settingsManager.downloads.qualityPreset,
                onSubmitSelection: { episodeIDs, quality, tracks, version in
                    for episodeID in episodeIDs {
                        await downloadManager.enqueueItem(
                            itemID: episodeID,
                            quality: quality,
                            tracks: tracks,
                            version: version,
                            services: mediaServices,
                        )
                    }
                },
                statusForIdentity: downloadManager.status,
            )
            .frame(minWidth: 520, minHeight: 600)
        }
        .sheet(isPresented: $isShowingDownloadOptions) {
            DownloadConfirmationSheet(
                itemID: viewModel.media.id,
                kind: viewModel.media.mediaKind,
                services: mediaServices,
                defaultQuality: settingsManager.downloads.qualityPreset,
            ) { quality, tracks, version in
                if viewModel.media.type == .season {
                    await downloadManager.enqueueItems(
                        itemID: viewModel.media.id,
                        kind: .season,
                        quality: quality,
                        tracks: tracks,
                        version: version,
                        services: mediaServices,
                    )
                } else {
                    await downloadManager.enqueueItem(
                        itemID: viewModel.media.id,
                        quality: quality,
                        tracks: tracks,
                        version: version,
                        services: mediaServices,
                    )
                }
            }
            .frame(minWidth: 480, minHeight: 420)
        }
        .sheet(isPresented: $isShowingSubtitleSearch) {
            if let ratingKey = viewModel.trackRatingKey {
                SubtitleSearchView(
                    itemID: ratingKey,
                    titlePlaceholder: viewModel.subtitleSearchTitlePlaceholder,
                    services: mediaServices,
                ) { _ in
                    await viewModel.refreshTrackSelectionAfterSubtitleAttachment()
                }
                .frame(minWidth: 560, minHeight: 640)
            }
        }
        .addToPlaylistPresentation(media: $mediaToAddToPlaylist, services: mediaServices)
        .sheet(isPresented: $isShowingFileInfo) {
            MediaFileInfoView(viewModel: viewModel)
                .frame(minWidth: 820, idealWidth: 920, minHeight: 620, idealHeight: 700)
        }
        .sheet(item: $sharePlaySharingRequest, onDismiss: {
            Task { await sharePlayCoordinator.sharingPresentationDidEnd() }
        }) { request in
            SharePlaySharingControllerView(controller: request.controller)
                .frame(minWidth: 420, minHeight: 420)
                .task {
                    let result = await request.controller.result
                    handleSharingResult(result, for: request.activity)
                }
        }
        .alert(
            "sharePlay.error.title",
            isPresented: Binding(
                get: { sharePlayCoordinator.errorMessage != nil },
                set: {
                    if !$0 {
                        sharePlayCoordinator.errorMessage = nil
                    }
                },
            ),
        ) {
            Button("common.actions.done") {
                sharePlayCoordinator.errorMessage = nil
            }
        } message: {
            Text(sharePlayCoordinator.errorMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
        .onConnectivityChange(of: mediaServices.identity) { _ in
            Task { await viewModel.refreshSilently() }
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

    private func playDownloaded(resumes: Bool) {
        if let request = downloadManager.localPlaybackRequest(forDetail: viewModel, resumes: resumes) {
            appModel.showLocalPlayer(request)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                Group {
                    if let url = viewModel.heroImageURL(
                        spoilerProtection: settingsManager.interface.spoilerProtection,
                    ) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.black.opacity(0.25)
                            }
                        }
                    } else {
                        ArtworkPathView(
                            path: viewModel.heroArtworkPath(
                                spoilerProtection: settingsManager.interface.spoilerProtection,
                            ),
                            width: 1400,
                            height: 800,
                        )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(Color.black.opacity(0.2))
                .mask(heroMask)
            }
            .frame(maxWidth: .infinity, minHeight: 380, maxHeight: 480)
            .overlay(alignment: .topLeading) {
                if viewModel.media.mediaItem.isSpoilerProtected(
                    at: settingsManager.interface.spoilerProtection,
                ) {
                    SpoilerProtectionIndicator()
                        .padding(16)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                DetailHeroTitle(viewModel: viewModel, alignment: .leading)
                if [.show, .season].contains(viewModel.media.type) {
                    DownloadedEpisodesLabel(media: viewModel.media.mediaItem)
                }

                if let parentSeries = viewModel.parentSeries {
                    Button("media.detail.openSeries", systemImage: "rectangle.stack.fill") {
                        onSelectParentSeries(parentSeries)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, minHeight: 380, maxHeight: 480)
    }

    private var heroMask: some View {
        LinearGradient(
            colors: [
                .white,
                .white,
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            actionButtons

            DetailPlaybackCard(
                viewModel: viewModel,
                isServerUnreachable: isServerUnreachable,
                onSearchSubtitles: { isShowingSubtitleSearch = true },
            )
            .frame(maxWidth: 520)

            if viewModel.media.mediaItem.shouldHideSpoilerSummary(
                at: settingsManager.interface.spoilerProtection,
            ) {
                Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
                    .font(.body)
                    .foregroundStyle(.textSecondary)
            } else if let summaryText {
                summaryText
                    .font(.body)
                    .foregroundStyle(.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 900, alignment: .leading)
            }

            if let error = viewModel.errorMessage
                ?? viewModel.watchActionErrorMessage
                ?? viewModel.favoriteActionErrorMessage
                ?? viewModel.trackSelectionErrorMessage
            {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 28)
    }

    /// The tagline leads the synopsis in semibold instead of taking a line of its own.
    private var summaryText: Text? {
        let tagline = viewModel.media.tagline.flatMap { $0.isEmpty ? nil : $0 }
        let summary = viewModel.media.summary.flatMap { $0.isEmpty ? nil : $0 }
        switch (tagline, summary) {
        case let (tagline?, summary?):
            return Text(verbatim: tagline + " ").fontWeight(.semibold).foregroundStyle(.textPrimary)
                + Text(verbatim: summary)
        case let (tagline?, nil):
            return Text(verbatim: tagline).fontWeight(.semibold).foregroundStyle(.textPrimary)
        case let (nil, summary?):
            return Text(verbatim: summary)
        case (nil, nil):
            return nil
        }
    }

    private var actionButtons: some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                playButton

                if isServerUnreachable, downloadedPlayback == nil {
                    if viewModel.reachableCopyReplacingUnavailableServer != nil {
                        ReachableCopyPlayButton(viewModel: viewModel, presenter: appModel)
                    } else {
                        Label("offline.detail.notAvailable", systemImage: "wifi.slash")
                            .font(.facts)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                watchStatusButton

                if viewModel.shouldShowFavoriteButton {
                    favoriteButton
                }

                if mediaServices.capabilities.downloads,
                   [.movie, .episode, .season, .show].contains(viewModel.media.type)
                {
                    Button(action: handleDownload) {
                        DetailCircleActionLabel(
                            systemImage: downloadIconName,
                            isActive: downloadStatus == .completed,
                            isLoading: isDownloadInProgress,
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading || isDownloadInProgress || isServerUnreachable)
                    .help(Text("downloads.action"))
                    .accessibilityLabel(Text("downloads.action"))
                }

                moreActionsMenu
            }
        }
    }

    private var playButton: some View {
        Button {
            if isServerUnreachable {
                playDownloaded(resumes: !viewModel.shouldPlayPrimaryActionFromStart)
                return
            }
            guard
                let ratingKey = viewModel.primaryActionRatingKey,
                let type = viewModel.primaryActionType
            else { return }
            onPlay(ratingKey, type, false, !viewModel.shouldPlayPrimaryActionFromStart)
        } label: {
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
            .frame(minWidth: 160)
        }
        .actionButtonStyle(.primary)
        .disabled(isPlayDisabled)
    }

    private var watchStatusButton: some View {
        Button {
            Task {
                if viewModel.shouldShowBothWatchActions {
                    await viewModel.markWatched()
                } else {
                    await viewModel.toggleWatchStatus()
                }
            }
        } label: {
            DetailCircleActionLabel(
                systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle",
                isActive: isWatched,
                isLoading: viewModel.isUpdatingWatchStatus,
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus || isServerUnreachable)
        .help(Text(
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
            DetailCircleActionLabel(
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
        .help(Text(viewModel.favoriteActionTitle))
    }

    private var moreActionsMenu: some View {
        Menu {
            if viewModel.shouldShowPlayFromStartButton,
               !isServerUnreachable || downloadedPlayback != nil,
               let ratingKey = viewModel.primaryActionRatingKey,
               let type = viewModel.primaryActionType
            {
                Button("media.detail.playFromStart", systemImage: "arrow.counterclockwise") {
                    if isServerUnreachable {
                        playDownloaded(resumes: false)
                    } else {
                        onPlay(ratingKey, type, false, false)
                    }
                }
            }

            if !isServerUnreachable, downloadedPlayback != nil {
                Button("offline.detail.playDownloaded", systemImage: "arrow.down.circle") {
                    playDownloaded(resumes: true)
                }
                .help(Text("offline.detail.playDownloaded.help"))
            }

            if !isServerUnreachable {
                if viewModel.media.type == .show || viewModel.media.type == .season {
                    Button("common.actions.shuffle", systemImage: "shuffle") {
                        onPlay(viewModel.media.id, viewModel.media.mediaKind, true, true)
                    }
                }

                if viewModel.shouldShowBothWatchActions {
                    Button("media.detail.watchAction.markUnwatched", systemImage: "checkmark.circle.fill") {
                        Task { await viewModel.markUnwatched() }
                    }
                    .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus)
                }

                if viewModel.shouldShowWatchlistButton {
                    Button(viewModel.watchlistActionTitle, systemImage: viewModel.watchlistActionIcon) {
                        Task { await viewModel.toggleWatchlistStatus() }
                    }
                    .disabled(viewModel.isUpdatingWatchlistStatus || viewModel.isLoadingWatchlistStatus)
                }

                if viewModel.primaryActionRatingKey != nil {
                    Button {
                        startSharePlay()
                    } label: {
                        if isStartingSharePlay {
                            Label {
                                Text("sharePlay.action")
                            } icon: {
                                ProgressView()
                            }
                        } else {
                            Label("sharePlay.action", systemImage: "shareplay")
                        }
                    }
                    .disabled(isStartingSharePlay)
                }

                if AddToPlaylistViewModel.canAdd(viewModel.media.mediaItem) {
                    Button("playlist.add.menuTitle", systemImage: "text.badge.plus") {
                        mediaToAddToPlaylist = viewModel.media.mediaItem
                    }
                }

                if viewModel.canShowFileInfo {
                    Divider()
                    Button("media.fileInfo.title", systemImage: "doc.text.magnifyingglass") {
                        isShowingFileInfo = true
                    }
                }
            }

            if !viewModel.listsCopiesWithVersions {
                MediaCopiesMenuItems(viewModel: viewModel)
            }
        } label: {
            DetailCircleActionLabel(
                systemImage: "ellipsis",
                isActive: false,
                isLoading: false,
                isHovered: isMoreMenuHovered,
            )
        }
        .onHover { isMoreMenuHovered = $0 }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("common.actions.more"))
        .accessibilityLabel(Text("common.actions.more"))
    }

    private var isStartingSharePlay: Bool {
        sharePlayCoordinator.isActivating || sharePlaySharingRequest != nil
    }

    private func startSharePlay() {
        guard
            let ratingKey = viewModel.primaryActionRatingKey,
            let playbackType = viewModel.primaryActionType,
            let item = viewModel.primaryActionItem, let activity = sharePlayCoordinator.makeActivity(
                ratingKey: ratingKey,
                type: playbackType,
                title: item.primaryLabel,
                initialPosition: viewModel.primaryActionInitialPosition,
                server: viewModel.server,
            ) else { return }

        if sharePlayCoordinator.isEligibleForGroupSession {
            Task { await sharePlayCoordinator.activate(activity) }
            return
        }

        do {
            let controller = try GroupActivitySharingController(activity)
            sharePlayCoordinator.sharingDidStart(activity)
            sharePlaySharingRequest = SharePlaySharingRequest(
                activity: activity,
                controller: controller,
            )
        } catch {
            guard !error.isCancellation else { return }
            ErrorReporter.capture(error)
            sharePlayCoordinator.errorMessage = String(localized: "sharePlay.error.unavailable")
        }
    }

    private func handleSharingResult(
        _ result: GroupActivitySharingResult,
        for activity: StrimrWatchActivity,
    ) {
        if result == .cancelled {
            sharePlayCoordinator.sharingDidCancel(activity)
        }
        sharePlaySharingRequest = nil
    }

    private func handleDownload() {
        switch viewModel.media.type {
        case .show:
            isShowingShowDownloadSheet = true
        case .season:
            isShowingDownloadOptions = true
        case .movie, .episode:
            isShowingDownloadOptions = true
        case .clip:
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
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle"
        case .queued, .preparing, .downloading: "arrow.down.circle.fill"
        case nil: "arrow.down.circle"
        }
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            MediaHubSection(
                title: String(localized: "media.detail.episodes.title"),
                subtitle: viewModel.episodes.isEmpty
                    ? nil
                    : String(localized: "media.labels.countEpisode \(viewModel.episodes.count)"),
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.media.type == .show {
                        SeasonPillsRow(viewModel: viewModel) { onSelectMedia($0) }
                    }
                    episodesContent
                }
            }
        }
        .padding(.horizontal, LayoutMetrics.detailSectionMargin)
    }

    @ViewBuilder
    private var episodesContent: some View {
        if viewModel.media.type == .show, viewModel.seasonsErrorMessage != nil || viewModel.seasons.isEmpty {
            // The season row above already shows the loading, error or empty state.
            EmptyView()
        } else if let error = viewModel.episodesErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
            ProgressView("media.detail.loadingEpisodes")
        } else if viewModel.episodes.isEmpty {
            Text("media.detail.noEpisodes")
                .font(.facts)
                .foregroundStyle(.textSecondary)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.episodes) { episode in
                    episodeRow(episode)
                }
            }
        }
    }

    private func episodeRow(_ episode: MediaItem) -> some View {
        Button {
            onSelectMedia(episode)
        } label: {
            HStack(spacing: 16) {
                EpisodeArtworkView(
                    episode: episode,
                    imageURL: viewModel.imageURL(
                        for: episode,
                        width: 640,
                        height: 360,
                        spoilerProtection: settingsManager.interface.spoilerProtection,
                    ),
                    width: 200,
                    runtime: nil,
                    progress: viewModel.progressFraction(for: episode),
                )

                EpisodeRowText(episode: episode, runtime: viewModel.runtimeText(for: episode), summaryLineLimit: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    if isServerUnreachable {
                        if let request = downloadManager.localPlaybackRequest(for: episode.identity, kind: .episode) {
                            appModel.showLocalPlayer(request)
                        }
                    } else {
                        onPlay(episode.id, episode.type, false, true)
                    }
                } label: {
                    Label("common.actions.play", systemImage: "play.fill")
                }
                .actionButtonStyle(.secondary)
                .disabled(isServerUnreachable && downloadManager.completedOwnedItem(for: episode.identity) == nil)
            }
            .padding(10)
            .modifier(EpisodeRowBackground())
        }
        .buttonStyle(.plain)
        .dimmedWhenUnavailableOffline(episode)
    }
}

private struct EpisodeRowBackground: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
        content
            .background(isHovered ? Color.surfaceRaised : Color.surfaceSubtle, in: shape)
            .contentShape(shape)
            .animation(Motion.focus, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

private struct SharePlaySharingRequest: Identifiable {
    let activity: StrimrWatchActivity
    let controller: GroupActivitySharingController

    var id: UUID {
        activity.activityID
    }
}
