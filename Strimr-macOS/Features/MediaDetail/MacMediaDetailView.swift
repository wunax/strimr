import SwiftUI

struct MacMediaDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: MediaDetailViewModel
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
        .background(MediaBackdropGradient(colors: viewModel.backdropGradient).ignoresSafeArea())
        .navigationTitle(viewModel.detailPrimaryLabel)
        .task { await viewModel.loadDetails() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: viewModel.heroImageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.black.opacity(0.25)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 340, maxHeight: 440)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom,
            )

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
        .frame(maxWidth: .infinity, minHeight: 340, maxHeight: 440)
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

            if let actionDetail = viewModel.primaryActionDetail {
                Text(actionDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let progress = viewModel.primaryActionProgress {
                ProgressView(value: progress)
                    .frame(maxWidth: 320)
                    .accessibilityLabel(Text(viewModel.primaryActionTitle))
            }

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
        HStack(spacing: 12) {
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
                Label(viewModel.primaryActionTitle, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.primaryActionRatingKey == nil)

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
                    Text(episode.tertiaryLabel ?? episode.title).font(.headline)
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
