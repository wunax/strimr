import AppKit
import GroupActivities
import SwiftUI

struct MacMediaDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlexAPIContext.self) private var context
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @State private var viewModel: MediaDetailViewModel
    @State private var isShowingShowDownloadSheet = false
    @State private var sharePlaySharingRequest: MacSharePlaySharingRequest?
    let onSelectMedia: (MediaItem) -> Void
    let onSelectParentSeries: (PlayableMediaItem) -> Void
    let onPlay: (String, PlexItemType, Bool, Bool) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onSelectMedia: @escaping (MediaItem) -> Void,
        onSelectParentSeries: @escaping (PlayableMediaItem) -> Void,
        onPlay: @escaping (String, PlexItemType, Bool, Bool) -> Void,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onSelectParentSeries = onSelectParentSeries
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

                    CastSection(viewModel: viewModel)
                    RelatedHubsSection(viewModel: viewModel) { media in
                        if case let .playable(item) = media {
                            onSelectMedia(item)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(viewModel.detailPrimaryLabel)
        .task { await viewModel.loadDetails() }
        .sheet(isPresented: $isShowingShowDownloadSheet) {
            MacShowDownloadSelectionSheet(
                viewModel: viewModel,
                onSubmitSelection: { episodeIDs in
                    for episodeID in episodeIDs {
                        await downloadManager.enqueueItem(ratingKey: episodeID, context: context)
                    }
                },
                statusForRatingKey: downloadManager.status,
            )
            .frame(minWidth: 520, minHeight: 600)
        }
        .sheet(item: $sharePlaySharingRequest, onDismiss: {
            Task { await sharePlayCoordinator.sharingPresentationDidEnd() }
        }) { request in
            MacSharePlaySharingControllerView(controller: request.controller)
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
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                AsyncImage(url: viewModel.heroImageURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .overlay(Color.black.opacity(0.2))
                            .mask(heroMask)
                    } else {
                        Color.black.opacity(0.25)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .mask(heroMask)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 380, maxHeight: 480)

            VStack(alignment: .leading, spacing: 8) {
                if let tagline = viewModel.media.tagline, !tagline.isEmpty {
                    Text(tagline).font(.headline).foregroundStyle(.secondary)
                }
                Text(viewModel.detailPrimaryLabel)
                    .font(.system(size: 36, weight: .bold))
                if let secondary = viewModel.detailSecondaryLabel {
                    Text(secondary)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                if let tertiary = viewModel.detailTertiaryLabel {
                    Text(tertiary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                metadataRow
                ratingsRow

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

    private var metadataRow: some View {
        HStack(spacing: 10) {
            if let year = viewModel.yearText {
                Text(year)
            }
            if let runtime = viewModel.runtimeText {
                Text(runtime)
            }
            if let contentRating = viewModel.media.contentRating {
                Text(contentRating)
            }
            if let rating = viewModel.ratingText {
                Label(rating, systemImage: "star.fill").foregroundStyle(.yellow)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var ratingsRow: some View {
        if !viewModel.media.ratings.isEmpty {
            HStack(spacing: 14) {
                ForEach(viewModel.media.ratings.indices, id: \.self) { index in
                    MediaRatingLabel(rating: viewModel.media.ratings[index], iconHeight: 16)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            actionButtons

            if let summary = viewModel.media.summary, !summary.isEmpty {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 900, alignment: .leading)
            }

            if !viewModel.media.genres.isEmpty {
                Text(viewModel.media.genres.joined(separator: " • "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.errorMessage ?? viewModel.watchActionErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 28)
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                guard
                    let ratingKey = viewModel.primaryActionRatingKey,
                    let type = viewModel.primaryActionType
                else { return }
                onPlay(
                    ratingKey,
                    type,
                    false,
                    !viewModel.shouldPlayPrimaryActionFromStart,
                )
            } label: {
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
                .frame(minWidth: 240, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.brandSecondary)
            .foregroundStyle(.brandSecondaryForeground)
            .disabled(viewModel.primaryActionRatingKey == nil)

            HStack(spacing: 12) {
                if viewModel.shouldShowPlayFromStartButton,
                   let ratingKey = viewModel.primaryActionRatingKey,
                   let type = viewModel.primaryActionType
                {
                    Button("common.actions.playFromStart", systemImage: "backward.end.fill") {
                        onPlay(ratingKey, type, false, false)
                    }
                    .controlSize(.large)
                }

                if viewModel.media.type == .show || viewModel.media.type == .season {
                    Button("common.actions.shuffle", systemImage: "shuffle") {
                        onPlay(viewModel.media.id, viewModel.media.plexType, true, true)
                    }
                    .controlSize(.large)
                }

                Button(viewModel.watchActionTitle, systemImage: viewModel.watchActionIcon) {
                    Task { await viewModel.toggleWatchStatus() }
                }
                .disabled(viewModel.isUpdatingWatchStatus)

                if viewModel.shouldShowWatchlistButton {
                    Button(viewModel.watchlistActionTitle, systemImage: viewModel.watchlistActionIcon) {
                        Task { await viewModel.toggleWatchlistStatus() }
                    }
                    .disabled(viewModel.isUpdatingWatchlistStatus || viewModel.isLoadingWatchlistStatus)
                }

                if [.movie, .episode, .season, .show].contains(viewModel.media.type) {
                    Button("downloads.action", systemImage: downloadIconName) {
                        handleDownload()
                    }
                    .disabled(viewModel.isLoading || isDownloadInProgress)
                }

                if viewModel.primaryActionRatingKey != nil {
                    Button {
                        startSharePlay()
                    } label: {
                        if isStartingSharePlay {
                            ProgressView()
                        } else {
                            Label("sharePlay.action", systemImage: "shareplay")
                        }
                    }
                    .disabled(isStartingSharePlay)
                    .accessibilityLabel(Text("sharePlay.action"))
                }
            }
        }
    }

    private var isStartingSharePlay: Bool {
        sharePlayCoordinator.isActivating || sharePlaySharingRequest != nil
    }

    private func startSharePlay() {
        guard
            let ratingKey = viewModel.primaryActionRatingKey,
            let playbackType = viewModel.primaryActionType,
            let item = viewModel.primaryActionItem
        else { return }
        guard let activity = sharePlayCoordinator.makeActivity(
            ratingKey: ratingKey,
            type: playbackType,
            title: item.primaryLabel,
            initialPosition: viewModel.primaryActionInitialPosition,
        ) else { return }

        if sharePlayCoordinator.isEligibleForGroupSession {
            Task { await sharePlayCoordinator.activate(activity) }
            return
        }

        do {
            let controller = try GroupActivitySharingController(activity)
            sharePlayCoordinator.sharingDidStart(activity)
            sharePlaySharingRequest = MacSharePlaySharingRequest(
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
            Task { await downloadManager.enqueueSeason(ratingKey: viewModel.media.id, context: context) }
        case .movie, .episode:
            Task { await downloadManager.enqueueItem(ratingKey: viewModel.media.id, context: context) }
        }
    }

    private var downloadStatus: DownloadStatus? {
        downloadManager.status(for: viewModel.media.id)
    }

    private var isDownloadInProgress: Bool {
        downloadStatus == .queued || downloadStatus == .downloading
    }

    private var downloadIconName: String {
        switch downloadStatus {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle"
        case .queued, .downloading: "arrow.down.circle.fill"
        case nil: "arrow.down.circle"
        }
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("media.detail.episodes.title").font(.title2.bold())
                Spacer()
                if viewModel.media.type == .show, !viewModel.seasons.isEmpty {
                    Menu {
                        ForEach(viewModel.seasons) { season in
                            Button {
                                if season.id == viewModel.selectedSeasonId {
                                    onSelectMedia(season)
                                } else {
                                    Task { await viewModel.selectSeason(id: season.id) }
                                }
                            } label: {
                                if season.id == viewModel.selectedSeasonId {
                                    Label(season.title, systemImage: "checkmark")
                                } else {
                                    Text(season.title)
                                }
                            }
                        }
                    } label: {
                        Label(viewModel.selectedSeasonTitle, systemImage: "chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if viewModel.media.type == .show,
               viewModel.isLoadingSeasons || viewModel.isLoading,
               viewModel.seasons.isEmpty
            {
                ProgressView("media.detail.loadingSeasons")
            } else if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
                ProgressView()
            } else if let error = viewModel.seasonsErrorMessage ?? viewModel.episodesErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else if viewModel.episodes.isEmpty {
                Text("media.detail.noEpisodes")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.episodes) { episode in
                        episodeRow(episode)
                    }
                }
            }
        }
        .padding(.horizontal, 28)
    }

    private func episodeRow(_ episode: MediaItem) -> some View {
        Button {
            onSelectMedia(episode)
        } label: {
            HStack(spacing: 14) {
                AsyncImage(url: viewModel.imageURL(for: episode)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.gray.opacity(0.15)
                    }
                }
                .frame(width: 180, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(episode.tertiaryLabel.map { "\($0) - \(episode.title)" } ?? episode.title)
                        .font(.headline)
                    if let summary = episode.summary {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Button("common.actions.play", systemImage: "play.fill") {
                    onPlay(episode.id, episode.type, false, true)
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MacSharePlaySharingRequest: Identifiable {
    let activity: StrimrWatchActivity
    let controller: GroupActivitySharingController

    var id: UUID {
        activity.activityID
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
