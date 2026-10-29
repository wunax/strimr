import Observation
import SwiftUI

struct MediaDetailView: View {
    @Environment(MediaServices.self) private var mediaServices
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(MediaFocusModel.self) private var focusModel
    @State var viewModel: MediaDetailViewModel
    @State private var focusedMedia: MediaItem?
    @State private var contextualEpisodeID: String?
    @State private var hasHandledInitialEpisodePosition = false
    @State private var hasUserSelectedSeason = false
    @State private var isShowingSubtitleSearch = false
    @State private var fileInfoMedia: MediaItem?
    @State private var expandedSummaryMedia: MediaItem?
    @State private var mediaToAddToPlaylist: MediaItem?
    @FocusState private var isPlayButtonFocused: Bool
    private let onPlay: (String, MediaKind) -> Void
    private let onPlayFromStart: (String, MediaKind) -> Void
    private let onShuffle: (String, MediaKind) -> Void
    private let onSelectMedia: (MediaDisplayItem) -> Void
    private let onSelectPerson: (Person) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String, MediaKind) -> Void = { _, _ in },
        onPlayFromStart: @escaping (String, MediaKind) -> Void = { _, _ in },
        onShuffle: @escaping (String, MediaKind) -> Void = { _, _ in },
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onSelectPerson: @escaping (Person) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onPlayFromStart = onPlayFromStart
        self.onShuffle = onShuffle
        self.onSelectMedia = onSelectMedia
        self.onSelectPerson = onSelectPerson
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        GeometryReader { proxy in
            ZStack {
                MediaHeroBackgroundView(media: bindableViewModel.media.mediaItem)

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        MediaHeroContentView(
                            media: heroMedia,
                            fallbackLogoPath: seriesLogoPath,
                            badges: heroBadges,
                            onExpandSummary: { expandedSummaryMedia = $0 },
                            // A series previews its seasons and episodes, which fill different lines.
                            reservedLines: showsEpisodes ? [.secondaryLabel, .facts, .summary] : [],
                            // The editions found belong to the page's title, not to a focused episode.
                            namesStandardEdition: !viewModel.otherEditions.isEmpty
                                && heroMedia.id == viewModel.media.id,
                        )
                        .frame(maxWidth: proxy.size.width * 0.60, alignment: .leading)

                        buttonsRow

                        DetailTrackPickers(
                            viewModel: bindableViewModel,
                            onSearchSubtitles: { isShowingSubtitleSearch = true },
                        )

                        if let trackSelectionErrorMessage = bindableViewModel.trackSelectionErrorMessage {
                            Label(trackSelectionErrorMessage, systemImage: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                        }

                        if showsEpisodes {
                            seasonsSection
                        }

                        CastSection(
                            viewModel: bindableViewModel,
                            onSelectPerson: onSelectPerson,
                        )
                        ExtrasSection(viewModel: bindableViewModel) { extra in
                            onPlay(extra.id, .clip)
                        }
                        RelatedHubsSection(viewModel: bindableViewModel, onSelectMedia: onSelectMedia)
                    }
                }
                .defaultFocus($isPlayButtonFocused, true)
            }
        }
        .task {
            await bindableViewModel.loadDetails()
        }
        .themeMusic(for: bindableViewModel.media.mediaItem)
        .taskPresentation(isPresented: $isShowingSubtitleSearch) {
            if let ratingKey = bindableViewModel.trackRatingKey {
                SubtitleSearchView(
                    itemID: ratingKey,
                    titlePlaceholder: bindableViewModel.subtitleSearchTitlePlaceholder,
                    services: mediaServices,
                ) { _ in
                    await bindableViewModel.refreshTrackSelectionAfterSubtitleAttachment()
                }
            }
        }
        .taskPresentation(item: $expandedSummaryMedia, style: .fullScreen) { media in
            DetailSummaryView(media: media, logoPath: media.preferredLogoPath ?? seriesLogoPath)
        }
        .addToPlaylistPresentation(media: $mediaToAddToPlaylist, services: mediaServices)
        .taskPresentation(item: $fileInfoMedia) { media in
            MediaFileInfoView(viewModel: bindableViewModel, targetMedia: media)
                .frame(minWidth: 900, idealWidth: 1080, minHeight: 640, idealHeight: 760)
                .presentationDetents([.height(760)])
        }
        .onChange(of: coordinator.isPresentingPlayer) { _, isPresenting in
            guard !isPresenting else { return }
            Task { await bindableViewModel.loadDetails() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onAppear {
            if focusedMedia == nil {
                focusedMedia = bindableViewModel.media.mediaItem
            }
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onChange(of: bindableViewModel.media) { oldValue, newValue in
            if focusedMedia == nil || focusedMedia?.id == oldValue.id {
                focusedMedia = newValue.mediaItem
            }
        }
        .onChange(of: bindableViewModel.episodes) { _, episodes in
            guard let contextualEpisodeID else { return }

            if let refreshedEpisode = episodes.first(where: { $0.id == contextualEpisodeID }) {
                focusedMedia = refreshedEpisode
            } else {
                self.contextualEpisodeID = nil
                if focusedMedia?.id == contextualEpisodeID {
                    focusedMedia = nil
                }
            }
        }
        .onChange(of: bindableViewModel.selectedSeasonId) {
            contextualEpisodeID = nil
        }
        .toolbar(.hidden, for: .tabBar)
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
        .alert(
            "media.detail.watchAction.error.title",
            isPresented: Binding(
                get: { bindableViewModel.watchActionErrorMessage != nil },
                set: {
                    if !$0 {
                        bindableViewModel.watchActionErrorMessage = nil
                    }
                },
            ),
        ) {
            Button("common.actions.done") {
                bindableViewModel.watchActionErrorMessage = nil
            }
        } message: {
            Text(bindableViewModel.watchActionErrorMessage ?? "")
        }
        .alert(
            "media.detail.favorite.error.title",
            isPresented: Binding(
                get: { bindableViewModel.favoriteActionErrorMessage != nil },
                set: {
                    if !$0 {
                        bindableViewModel.favoriteActionErrorMessage = nil
                    }
                },
            ),
        ) {
            Button("common.actions.done") {
                bindableViewModel.favoriteActionErrorMessage = nil
            }
        } message: {
            Text(bindableViewModel.favoriteActionErrorMessage ?? "")
        }
    }

    private var contextualEpisode: MediaItem? {
        guard let contextualEpisodeID else { return nil }
        return viewModel.episodes.first(where: { $0.id == contextualEpisodeID })
    }

    private var showsEpisodes: Bool {
        viewModel.media.type == .show
    }

    private var heroMedia: MediaItem {
        contextualEpisode ?? focusedMedia ?? viewModel.media.mediaItem
    }

    /// Plex only returns a logo on the series itself, so its episodes and seasons borrow it from the loaded series.
    private var seriesLogoPath: String? {
        (viewModel.parentSeries ?? viewModel.media).mediaItem.logoPath
    }

    /// Badges of the version that would play, once its tracks are loaded for the item the hero shows.
    private var heroBadges: [String]? {
        guard viewModel.activeVersionID(for: heroMedia) != nil else { return nil }
        return viewModel.selectedVersion?.badgeLabels
    }

    private var playButton: some View {
        Button(action: handlePlay) {
            HStack(spacing: 12) {
                PlayProgressIcon(progress: viewModel.primaryActionProgress)
                Text(viewModel.primaryActionCompactTitle)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let remainingTime = viewModel.primaryActionRemainingTime {
                    Text(verbatim: "· \(remainingTime)")
                        .foregroundStyle(Color.black.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .font(.facts.weight(.semibold))
            .padding(.horizontal, 12)
        }
        .actionButtonStyle(.primary)
        // Kept enabled while a series resolves its next episode, so the initial focus can land on it.
        .focused($isPlayButtonFocused)
    }

    private var buttonsRow: some View {
        HStack(spacing: 16) {
            playButton

            if viewModel.shouldShowPlayFromStartButton {
                playFromStartButton
            }

            ReachableCopyPlayButton(viewModel: viewModel, presenter: coordinator)

            watchStatusButton

            if viewModel.shouldShowFavoriteButton {
                favoriteButton
            }

            moreActionsMenu
        }
        // Full width so moving up from the right side of a rail below still lands on an action.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var playFromStartButton: some View {
        Button(action: handlePlayFromStart) {
            DetailRoundIcon(systemImage: "arrow.counterclockwise")
        }
        .detailRoundButtonStyle()
        .accessibilityLabel(Text("media.detail.playFromStart"))
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
            DetailRoundIcon(systemImage: viewModel.watchActionIcon, isLoading: viewModel.isUpdatingWatchStatus)
        }
        .detailRoundButtonStyle()
        .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus)
        .accessibilityLabel(Text(
            viewModel.shouldShowBothWatchActions
                ? String(localized: "media.detail.watchAction.markWatched")
                : viewModel.watchActionTitle,
        ))
    }

    private var favoriteButton: some View {
        Button {
            Task { await viewModel.toggleFavoriteStatus() }
        } label: {
            DetailRoundIcon(
                systemImage: viewModel.favoriteActionIcon,
                isLoading: viewModel.isLoadingFavoriteStatus || viewModel.isUpdatingFavoriteStatus,
            )
        }
        .detailRoundButtonStyle()
        .disabled(viewModel.isLoading || viewModel.isLoadingFavoriteStatus || viewModel.isUpdatingFavoriteStatus)
        .accessibilityLabel(Text(viewModel.favoriteActionTitle))
    }

    private var shouldShowShuffleAction: Bool {
        [.show, .season].contains(viewModel.media.type)
    }

    private var isPerformingMenuAction: Bool {
        sharePlayCoordinator.isActivating
            || viewModel.isUpdatingWatchStatus
            || viewModel.isUpdatingWatchlistStatus
    }

    private var moreActionsMenu: some View {
        Menu {
            if shouldShowShuffleAction {
                Button(action: handleShuffle) {
                    Label("common.actions.shuffle", systemImage: "shuffle")
                }
            }

            Button {
                Task { await activateSharePlay() }
            } label: {
                if sharePlayCoordinator.isActivating {
                    Label {
                        Text("sharePlay.action")
                    } icon: {
                        ProgressView()
                    }
                } else {
                    Label("sharePlay.action", systemImage: "shareplay")
                }
            }
            .disabled(sharePlayCoordinator.isActivating)

            // The round button marks an in-progress item watched; clearing its progress only lives here.
            if viewModel.shouldShowBothWatchActions {
                Button {
                    Task { await viewModel.markUnwatched() }
                } label: {
                    Label("media.detail.watchAction.markUnwatched", systemImage: "checkmark.circle.fill")
                }
                .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus)
            }

            if viewModel.shouldShowWatchlistButton {
                Button {
                    Task { await viewModel.toggleWatchlistStatus() }
                } label: {
                    if viewModel.isLoadingWatchlistStatus || viewModel.isUpdatingWatchlistStatus {
                        Label {
                            Text(viewModel.watchlistActionTitle)
                        } icon: {
                            ProgressView()
                        }
                    } else {
                        Label(viewModel.watchlistActionTitle, systemImage: viewModel.watchlistActionIcon)
                    }
                }
                .disabled(
                    viewModel.isLoading
                        || viewModel.isLoadingWatchlistStatus
                        || viewModel.isUpdatingWatchlistStatus,
                )
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
                Button {
                    fileInfoMedia = viewModel.media.mediaItem
                } label: {
                    Label("media.fileInfo.title", systemImage: "doc.text.magnifyingglass")
                }
            }

            if !viewModel.listsCopiesWithVersions {
                MediaCopiesMenuItems(viewModel: viewModel)
            }
        } label: {
            DetailRoundIcon(systemImage: "ellipsis", isLoading: isPerformingMenuAction)
        }
        .detailRoundButtonStyle()
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("common.actions.more"))
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 32) {
            seasonSelector
            episodesRow
        }
    }

    @ViewBuilder
    private var seasonSelector: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingSeasons || viewModel.isLoading, viewModel.seasons.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("media.detail.loadingSeasons")
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasons")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutMetrics.chipSpacing) {
                    ForEach(viewModel.seasons) { season in
                        SeasonPillButton(
                            title: season.title,
                            isSelected: season.id == viewModel.selectedSeasonId,
                            onSelect: {
                                if season.id != viewModel.selectedSeasonId {
                                    hasUserSelectedSeason = true
                                }
                                Task { await viewModel.selectSeason(id: season.id) }
                            },
                            onFocus: {
                                focusModel.settle { focusedMedia = season }
                            },
                            onBlur: {
                                focusModel.settle {
                                    if focusedMedia?.id == season.id {
                                        focusedMedia = nil
                                    }
                                }
                            },
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .focusSection()
        }
    }

    @ViewBuilder
    private var episodesRow: some View {
        if let error = viewModel.episodesErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
            HStack(alignment: .top, spacing: episodeSpacing) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    EpisodeSkeletonCard(width: episodeWidth)
                }
            }
            .padding(.vertical, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("media.detail.loadingEpisodes"))
        } else if viewModel.episodes.isEmpty {
            Text("media.detail.noEpisodes")
                .foregroundStyle(.secondary)
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: episodeSpacing) {
                        ForEach(viewModel.episodes) { episode in
                            EpisodeArtworkCard(
                                episode: episode,
                                imageURL: viewModel.imageURL(
                                    for: episode,
                                    width: 640,
                                    height: 360,
                                    spoilerProtection: settingsManager.interface.spoilerProtection,
                                ),
                                runtime: viewModel.runtimeText(for: episode),
                                progress: viewModel.progressFraction(for: episode),
                                width: episodeWidth,
                                shouldShowPlayFromStart: viewModel.shouldShowPlayFromStartButton(for: episode),
                                watchActionIcon: viewModel.watchActionIcon(for: episode),
                                watchActionTitle: viewModel.watchActionTitle(for: episode),
                                isUpdatingWatchStatus: viewModel.isUpdatingWatchStatus(for: episode),
                                isStartingSharePlay: sharePlayCoordinator.isActivating,
                                trackViewModel: viewModel,
                                onPlay: {
                                    onPlay(episode.id, .episode)
                                },
                                onPlayFromStart: {
                                    onPlayFromStart(episode.id, .episode)
                                },
                                onSharePlay: {
                                    Task { await activateSharePlay(for: episode) }
                                },
                                onToggleWatchStatus: {
                                    Task { await viewModel.toggleWatchStatus(for: episode) }
                                },
                                onMarkUnwatched: {
                                    Task { await viewModel.markUnwatched(for: episode) }
                                },
                                shouldShowBothWatchActions: viewModel.shouldShowBothWatchActions(for: episode),
                                onMarkWatched: {
                                    Task { await viewModel.markWatched(for: episode) }
                                },
                                isOnDeck: viewModel.onDeckItem?.id == episode.id,
                                onFocus: {
                                    focusModel.settle {
                                        contextualEpisodeID = episode.id
                                        focusedMedia = episode
                                        Task { await viewModel.loadTrackSelection(for: episode.id) }
                                    }
                                },
                                onFileInfo: {
                                    fileInfoMedia = episode
                                },
                            )
                            .id(episode.id)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.vertical, 4)
                }
                .task(id: viewModel.episodes.map(\.id)) {
                    await positionOnDeckEpisodeIfNeeded(using: scrollProxy)
                }
                .focusSection()
            }
        }
    }

    private let episodeWidth: CGFloat = 460
    private let episodeSpacing: CGFloat = 36

    @MainActor
    private func positionOnDeckEpisodeIfNeeded(using scrollProxy: ScrollViewProxy) async {
        guard !hasHandledInitialEpisodePosition, !hasUserSelectedSeason else { return }
        hasHandledInitialEpisodePosition = true

        guard let primaryEpisodeID = viewModel.primaryActionItem?.id,
              viewModel.episodes.contains(where: { $0.id == primaryEpisodeID }) else { return }

        await Task.yield()

        guard !Task.isCancelled, !hasUserSelectedSeason, viewModel.primaryActionItem?.id == primaryEpisodeID,
              viewModel.episodes.contains(where: { $0.id == primaryEpisodeID }) else { return }

        scrollProxy.scrollTo(primaryEpisodeID, anchor: .leading)
    }

    private func handlePlay() {
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

    private func activateSharePlay() async {
        guard
            let ratingKey = viewModel.primaryActionRatingKey,
            let playbackType = viewModel.primaryActionType,
            let item = viewModel.primaryActionItem
        else { return }
        await sharePlayCoordinator.activate(
            ratingKey: ratingKey,
            type: playbackType,
            title: item.primaryLabel,
            initialPosition: viewModel.primaryActionInitialPosition,
            server: viewModel.server,
        )
    }

    private func activateSharePlay(for episode: MediaItem) async {
        await sharePlayCoordinator.activate(
            ratingKey: episode.id,
            type: .episode,
            title: episode.primaryLabel,
            initialPosition: episode.isFullyWatched ? 0 : Double(episode.viewOffset ?? 0),
            server: viewModel.server,
        )
    }
}

private struct EpisodeArtworkCard: View {
    let episode: MediaItem
    let imageURL: URL?
    let runtime: String?
    let progress: Double?
    let width: CGFloat
    let shouldShowPlayFromStart: Bool
    let watchActionIcon: String
    let watchActionTitle: String
    let isUpdatingWatchStatus: Bool
    let isStartingSharePlay: Bool
    @Bindable var trackViewModel: MediaDetailViewModel
    let onPlay: () -> Void
    let onPlayFromStart: () -> Void
    let onSharePlay: () -> Void
    let onToggleWatchStatus: () -> Void
    let onMarkUnwatched: () -> Void
    let shouldShowBothWatchActions: Bool
    let onMarkWatched: () -> Void
    let isOnDeck: Bool
    let onFocus: () -> Void
    let onFileInfo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            artwork
            caption
        }
        .frame(width: width, alignment: .leading)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([episodeNumberText, runtime].compactMap(\.self).joined(separator: " · "))
                .eyebrowStyle()
                .foregroundStyle(.textTertiary)
                .opacity(isFocused ? 1 : 0.32 / 0.45)
                .lineLimit(1)
            Text(episode.title)
                .font(.cardTitle)
                .foregroundStyle(.textPrimary.opacity(isFocused ? 1 : 0.45))
                .lineLimit(1)
        }
        // Follows the bottom edge of the focused artwork so the lifted card does not cover its caption.
        .offset(y: isFocused && !reduceMotion ? width / (16 / 9) * (CardFocusStyle.focusedScale - 1) / 2 : 0)
        .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isFocused)
    }

    private var episodeNumberText: String {
        guard let index = episode.index else { return String(localized: "search.fallback.episode") }
        return String(localized: "media.detail.episodeNumber \(index)")
    }

    @ViewBuilder
    private var onDeckBadge: some View {
        if isOnDeck {
            Text(progress != nil ? "media.detail.episode.inProgress" : "media.detail.episode.upNext")
                .font(.badge)
                .textCase(.uppercase)
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.badgeBackground, in: Capsule(style: .continuous))
                .padding(12)
        }
    }

    private var artwork: some View {
        EpisodeArtworkView(
            episode: episode,
            imageURL: imageURL,
            width: width,
            runtime: nil,
            progress: progress,
        )
        .overlay(alignment: .topLeading) {
            onDeckBadge
        }
        .focusable()
        .focused($isFocused)
        .overlay(alignment: .trailing) {
            if isFocused {
                Group {
                    if isStartingSharePlay
                        || isUpdatingWatchStatus
                        || trackViewModel.isUpdatingFavoriteStatus(for: episode)
                    {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .rotationEffect(.degrees(90))
                    }
                }
                .frame(width: 24, height: 24)
                .frame(width: 48, height: 48)
                .glassSurface(in: Circle())
                .padding(12)
                .accessibilityHidden(true)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .cardFocusStyle(isFocused: isFocused)
        .contextMenu {
            if shouldShowPlayFromStart {
                Button(action: onPlayFromStart) {
                    Label("media.detail.playFromStart", systemImage: "arrow.counterclockwise")
                }
            }

            Button(action: onSharePlay) {
                Label("sharePlay.action", systemImage: "shareplay")
            }
            .disabled(isStartingSharePlay)

            if shouldShowBothWatchActions {
                Button(action: onMarkWatched) {
                    Label(
                        "media.detail.watchAction.markWatched",
                        systemImage: "checkmark.circle",
                    )
                }
                .disabled(isUpdatingWatchStatus)

                Button(action: onMarkUnwatched) {
                    Label(
                        "media.detail.watchAction.markUnwatched",
                        systemImage: "checkmark.circle.fill",
                    )
                }
                .disabled(isUpdatingWatchStatus)
            } else {
                Button(action: onToggleWatchStatus) {
                    Label(watchActionTitle, systemImage: watchActionIcon)
                }
                .disabled(isUpdatingWatchStatus)
            }

            if trackViewModel.shouldShowFavoriteButton(for: episode) {
                Button {
                    Task { await trackViewModel.toggleFavoriteStatus(for: episode) }
                } label: {
                    if trackViewModel.isLoadingFavoriteStatus(for: episode)
                        || trackViewModel.isUpdatingFavoriteStatus(for: episode)
                    {
                        Label {
                            Text(trackViewModel.favoriteActionTitle(for: episode))
                        } icon: {
                            ProgressView()
                        }
                    } else {
                        Label(
                            trackViewModel.favoriteActionTitle(for: episode),
                            systemImage: trackViewModel.favoriteActionIcon(for: episode),
                        )
                    }
                }
                .disabled(
                    trackViewModel.isLoadingFavoriteStatus(for: episode)
                        || trackViewModel.isUpdatingFavoriteStatus(for: episode),
                )
            }

            if trackViewModel.hasTrackSelection(for: episode.id) {
                Divider()
                MediaDetailTrackMenuItems(viewModel: trackViewModel, ratingKey: episode.id)
            }

            Divider()
            Button(action: onFileInfo) {
                Label("media.fileInfo.title", systemImage: "doc.text.magnifyingglass")
            }
        }
        .onPlayPauseCommand(perform: onPlay)
        .onTapGesture(perform: onPlay)
        .animation(Motion.focus, value: isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                onFocus()
                Task { await trackViewModel.loadFavoriteStatus(for: episode) }
            }
        }
    }
}

/// Same footprint as an episode card, so switching seasons does not change the page height.
struct EpisodeSkeletonCard: View {
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: MediaArtworkMetrics.compactCornerRadius, style: .continuous)
                .fill(.surfaceSubtle)
                .frame(width: width, height: width * 9 / 16)
            VStack(alignment: .leading, spacing: 4) {
                SkeletonLine(font: .cardTitle, fraction: 0.7)
                SkeletonLine(font: .cardMetadata, fraction: 0.25)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Icon of a round button beside Play. A fixed box keeps every circle the same size, a little shorter than Play,
/// whatever the glyph's own height.
private struct DetailRoundIcon: View {
    let systemImage: String
    var isLoading = false

    var body: some View {
        ZStack {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .frame(width: 28, height: 28)
    }
}

private extension View {
    /// Round icon button beside Play; the system bordered style keeps the native tvOS focus lift.
    func detailRoundButtonStyle() -> some View {
        buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
    }
}
