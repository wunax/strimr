import Observation
import SwiftUI

struct MediaDetailView: View {
    @Environment(MediaServices.self) private var mediaServices
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(MediaFocusModel.self) private var focusModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var viewModel: MediaDetailViewModel
    @FocusState private var focus: MediaDetailFocus?
    /// `focus` once it has rested, which the hero follows.
    @State private var settledFocus: MediaDetailFocus?
    /// The episode the bar under the rail acts on: the last one focused, the next one to watch until then.
    @State private var selectedEpisodeID: String?
    @State private var pageScrollPosition = ScrollPosition(edge: .top)
    /// Focus is on the episodes or their bar, so the logo shrinks to fit them under the hero.
    @State private var isBrowsingEpisodes = false
    @State private var hasHandledInitialEpisodePosition = false
    @State private var hasUserSelectedSeason = false
    @State private var isShowingSubtitleSearch = false
    @State private var fileInfoMedia: MediaItem?
    @State private var expandedSummaryMedia: MediaItem?
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
                    VStack(alignment: .leading, spacing: 24) {
                        MediaHeroContentView(
                            media: heroMedia,
                            fallbackLogoPath: seriesLogoPath,
                            // A series keeps the room for its episode bar; its cast follows just below anyway.
                            starring: heroMedia.id == bindableViewModel.media.id && !showsEpisodes
                                ? StarringFormatter.text(from: bindableViewModel.cast) : nil,
                            badges: heroBadges,
                            onExpandSummary: { expandedSummaryMedia = $0 },
                            // A series previews its seasons and episodes, which fill different lines; a movie only
                            // gains its cast once loaded.
                            reservedLines: showsEpisodes ? [.secondaryLabel, .facts, .summary] : [.starring],
                            compactsLogo: isBrowsingEpisodes,
                        )
                        .frame(maxWidth: proxy.size.width * 0.60, alignment: .leading)

                        buttonsRow

                        if showsEpisodes {
                            seasonsSection
                        } else {
                            DetailTrackPickers(
                                viewModel: bindableViewModel,
                                onSearchSubtitles: { isShowingSubtitleSearch = true },
                            )
                            trackSelectionError
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
                .scrollPosition($pageScrollPosition)
                // The system scrolls to give the focused control room from the edge, which on a series would slide
                // the hero away from where the home left it just to reach the episode bar.
                .scrollDisabled(keepsFirstScreen)
            }
        }
        .task {
            await bindableViewModel.loadDetails()
            await loadSelectedEpisodeTracks()
        }
        .themeMusic(path: bindableViewModel.media.mediaItem.themePath)
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
        .taskPresentation(item: $fileInfoMedia) { media in
            MediaFileInfoView(viewModel: bindableViewModel, targetMedia: media)
                .frame(minWidth: 900, idealWidth: 1080, minHeight: 640, idealHeight: 760)
                .presentationDetents([.height(760)])
        }
        .onChange(of: coordinator.isPresentingPlayer) { _, isPresenting in
            guard !isPresenting else { return }
            Task {
                await bindableViewModel.loadDetails()
                await loadSelectedEpisodeTracks()
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onAppear {
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onChange(of: focus) { oldValue, newValue in
            withAnimation(Motion.animation(Motion.pageScroll, reduceMotion: reduceMotion)) {
                switch newValue {
                case .episode, .episodeBar:
                    isBrowsingEpisodes = true
                case .season, .pageActions:
                    isBrowsingEpisodes = false
                case nil:
                    // A menu of the bar, the summary or the sections below: the logo keeps its size.
                    break
                }
            }
            if isInFirstScreen(newValue), !isInFirstScreen(oldValue) {
                scrollFirstScreen()
            }
            focusModel.settle {
                settledFocus = newValue
                if case let .episode(id) = newValue {
                    selectedEpisodeID = id
                }
            }
        }
        .onChange(of: bindableViewModel.episodes) { _, episodes in
            if let selectedEpisodeID, !episodes.contains(where: { $0.id == selectedEpisodeID }) {
                self.selectedEpisodeID = nil
            }
        }
        .onChange(of: bindableViewModel.selectedSeasonId) {
            selectedEpisodeID = nil
        }
        .task(id: selectedEpisode?.id) {
            await loadSelectedEpisodeTracks()
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

    private var showsEpisodes: Bool {
        viewModel.media.type == .show
    }

    /// The hero, its actions, the seasons, the episodes and their bar share the first screen; only what follows
    /// them scrolls.
    private func isInFirstScreen(_ focus: MediaDetailFocus?) -> Bool {
        guard showsEpisodes, let focus else { return false }
        return switch focus {
        case .season, .episode, .episodeBar, .pageActions: true
        }
    }

    private var keepsFirstScreen: Bool {
        isInFirstScreen(focus)
    }

    private func scrollFirstScreen() {
        withAnimation(Motion.animation(Motion.pageScroll, reduceMotion: reduceMotion)) {
            pageScrollPosition.scrollTo(edge: .top)
        }
    }

    private var selectedEpisode: MediaItem? {
        let episodes = viewModel.episodes
        return episodes.first { $0.id == selectedEpisodeID }
            ?? episodes.first { $0.id == viewModel.primaryActionItem?.id }
            ?? episodes.first
    }

    /// The series by default; a season or an episode only while focus rests on it or on the episode bar.
    private var heroMedia: MediaItem {
        switch settledFocus {
        case let .season(id):
            viewModel.seasons.first { $0.id == id } ?? viewModel.media.mediaItem
        case let .episode(id):
            viewModel.episodes.first { $0.id == id } ?? viewModel.media.mediaItem
        case .episodeBar:
            selectedEpisode ?? viewModel.media.mediaItem
        case .pageActions, nil:
            viewModel.media.mediaItem
        }
    }

    private func loadSelectedEpisodeTracks() async {
        guard showsEpisodes, let episode = selectedEpisode else { return }
        await viewModel.loadTrackSelection(for: episode.id)
    }

    @ViewBuilder
    private var trackSelectionError: some View {
        if let trackSelectionErrorMessage = viewModel.trackSelectionErrorMessage {
            Label(trackSelectionErrorMessage, systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
        }
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
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.white)
        .foregroundStyle(.black)
        .disabled(viewModel.primaryActionRatingKey == nil)
    }

    private var buttonsRow: some View {
        HStack(spacing: 16) {
            playButton
                .focused($focus, equals: .pageActions)

            if viewModel.shouldShowPlayFromStartButton {
                playFromStartButton
                    .focused($focus, equals: .pageActions)
            }

            ReachableCopyPlayButton(viewModel: viewModel, presenter: coordinator)
                .focused($focus, equals: .pageActions)

            watchStatusButton
                .focused($focus, equals: .pageActions)

            if viewModel.shouldShowFavoriteButton {
                favoriteButton
                    .focused($focus, equals: .pageActions)
            }

            moreActionsMenu
                .focused($focus, equals: .pageActions)
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

            if viewModel.canShowFileInfo {
                Divider()
                Button {
                    fileInfoMedia = viewModel.media.mediaItem
                } label: {
                    Label("media.fileInfo.title", systemImage: "doc.text.magnifyingglass")
                }
            }
        } label: {
            DetailRoundIcon(systemImage: "ellipsis", isLoading: isPerformingMenuAction)
        }
        .detailRoundButtonStyle()
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("common.actions.more"))
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            seasonSelector
            episodesRow
            episodeBar
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
                HStack(spacing: 16) {
                    ForEach(viewModel.seasons) { season in
                        SeasonPillButton(
                            title: season.title,
                            isSelected: season.id == viewModel.selectedSeasonId,
                            isFocused: focus == .season(season.id),
                            onSelect: {
                                if season.id != viewModel.selectedSeasonId {
                                    hasUserSelectedSeason = true
                                }
                                Task { await viewModel.selectSeason(id: season.id) }
                            },
                        )
                        .focused($focus, equals: .season(season.id))
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
                                isSelected: episode.id == selectedEpisode?.id,
                                isDimmed: focus == .episodeBar && episode.id != selectedEpisode?.id,
                                isFocused: focus == .episode(episode.id),
                                focus: $focus,
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
                // Coming back from the episode bar, or down from the seasons, lands on the episode the bar acts on.
                .defaultFocus($focus, selectedEpisode.map { .episode($0.id) }, priority: .userInitiated)
            }
        }
    }

    @ViewBuilder
    private var episodeBar: some View {
        if let episode = selectedEpisode {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    if viewModel.shouldShowPlayFromStartButton(for: episode) {
                        Button {
                            onPlayFromStart(episode.id, .episode)
                        } label: {
                            DetailRoundIcon(systemImage: "arrow.counterclockwise")
                        }
                        .detailRoundButtonStyle()
                        .focused($focus, equals: .episodeBar)
                        .accessibilityLabel(Text("media.detail.playFromStart"))
                    }

                    episodeWatchStatusButton(for: episode)

                    if viewModel.shouldShowFavoriteButton(for: episode) {
                        episodeFavoriteButton(for: episode)
                    }

                    // The previous episode's pills stay while the next one's tracks load, so moving along the rail
                    // updates their values in place instead of removing and re-adding them.
                    if viewModel.hasTrackSelection {
                        DetailTrackPickers(
                            viewModel: viewModel,
                            onSearchSubtitles: { isShowingSubtitleSearch = true },
                            focus: $focus,
                        )
                    }

                    episodeMoreMenu(for: episode)
                }

                trackSelectionError
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
            .task(id: episode.id) {
                await viewModel.loadFavoriteStatus(for: episode)
            }
        }
    }

    private func episodeWatchStatusButton(for episode: MediaItem) -> some View {
        let showsBothActions = viewModel.shouldShowBothWatchActions(for: episode)
        let isUpdating = viewModel.isUpdatingWatchStatus(for: episode)
        return Button {
            Task {
                if showsBothActions {
                    await viewModel.markWatched(for: episode)
                } else {
                    await viewModel.toggleWatchStatus(for: episode)
                }
            }
        } label: {
            DetailRoundIcon(systemImage: viewModel.watchActionIcon(for: episode), isLoading: isUpdating)
        }
        .detailRoundButtonStyle()
        .disabled(isUpdating)
        .focused($focus, equals: .episodeBar)
        .accessibilityLabel(Text(
            showsBothActions
                ? String(localized: "media.detail.watchAction.markWatched")
                : viewModel.watchActionTitle(for: episode),
        ))
    }

    private func episodeFavoriteButton(for episode: MediaItem) -> some View {
        // Only an update shows a spinner; loading the status of each episode passed in the rail would blink it.
        let isUpdating = viewModel.isUpdatingFavoriteStatus(for: episode)
        return Button {
            // Ignored rather than disabled while the status loads, which would dim the button for the same reason.
            guard !viewModel.isLoadingFavoriteStatus(for: episode) else { return }
            Task { await viewModel.toggleFavoriteStatus(for: episode) }
        } label: {
            DetailRoundIcon(systemImage: viewModel.favoriteActionIcon(for: episode), isLoading: isUpdating)
        }
        .detailRoundButtonStyle()
        .disabled(isUpdating)
        .focused($focus, equals: .episodeBar)
        .accessibilityLabel(Text(viewModel.favoriteActionTitle(for: episode)))
    }

    private func episodeMoreMenu(for episode: MediaItem) -> some View {
        Menu {
            Button {
                Task { await activateSharePlay(for: episode) }
            } label: {
                Label("sharePlay.action", systemImage: "shareplay")
            }
            .disabled(sharePlayCoordinator.isActivating)

            if viewModel.shouldShowBothWatchActions(for: episode) {
                Button {
                    Task { await viewModel.markUnwatched(for: episode) }
                } label: {
                    Label("media.detail.watchAction.markUnwatched", systemImage: "checkmark.circle.fill")
                }
                .disabled(viewModel.isUpdatingWatchStatus(for: episode))
            }

            Divider()
            Button {
                fileInfoMedia = episode
            } label: {
                Label("media.fileInfo.title", systemImage: "doc.text.magnifyingglass")
            }
        } label: {
            DetailRoundIcon(systemImage: "ellipsis", isLoading: sharePlayCoordinator.isActivating)
        }
        .detailRoundButtonStyle()
        .menuIndicator(.hidden)
        .focused($focus, equals: .episodeBar)
        .accessibilityLabel(Text("common.actions.more"))
    }

    private let episodeWidth: CGFloat = 420
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

enum MediaDetailFocus: Hashable {
    case season(String)
    case episode(String)
    /// Any control of the bar acting on the selected episode.
    case episodeBar
    /// Play and the round buttons beside it.
    case pageActions
}

private struct SeasonPillButton: View {
    let title: String
    let isSelected: Bool
    let isFocused: Bool
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(title)
            .font(.facts.weight(.semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? Color.black : Color.textPrimary)
            .background(Capsule(style: .continuous).fill(background))
            .scaleEffect(isFocused && !reduceMotion ? CardFocusStyle.focusedScale : 1)
            .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: isFocused)
            .animation(Motion.crossfade, value: isSelected)
            .focusable()
            .onPlayPauseCommand(perform: onSelect)
            .onTapGesture(perform: onSelect)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected {
            return .white
        }
        return isFocused ? .white.opacity(0.3) : .surfaceRaised
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
    /// The episode the bar under the rail acts on; its caption stays lit once focus moves to the bar.
    let isSelected: Bool
    /// Set on the other episodes while focus is on the bar, so the one it acts on stands out.
    let isDimmed: Bool
    let isFocused: Bool
    let focus: FocusState<MediaDetailFocus?>.Binding
    let onFileInfo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            artwork
            caption
        }
        .frame(width: width, alignment: .leading)
        .opacity(isDimmed ? 0.4 : 1)
        .animation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion), value: isDimmed)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([episodeNumberText, runtime].compactMap(\.self).joined(separator: " · "))
                .eyebrowStyle()
                .foregroundStyle(.textTertiary)
                .opacity(isFocused || isSelected ? 1 : 0.32 / 0.45)
                .lineLimit(1)
            Text(episode.title)
                .font(.cardTitle)
                .foregroundStyle(.textPrimary.opacity(isFocused || isSelected ? 1 : 0.45))
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
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.brandPrimary, in: Capsule(style: .continuous))
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
        .focused(focus, equals: .episode(episode.id))
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
    }
}

/// Same footprint as an episode card, so switching seasons does not change the page height.
private struct EpisodeSkeletonCard: View {
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
