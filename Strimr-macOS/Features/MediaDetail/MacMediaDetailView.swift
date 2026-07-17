import SwiftUI

struct MacMediaDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: MediaDetailViewModel
    let onSelectMedia: (MediaItem) -> Void
    let onPlay: (String, PlexItemType, Bool, Bool) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onSelectMedia: @escaping (MediaItem) -> Void,
        onPlay: @escaping (String, PlexItemType, Bool, Bool) -> Void,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onPlay = onPlay
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                hero
                details

                if viewModel.media.type == .show {
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
        .navigationTitle(viewModel.media.title)
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
                Text(viewModel.media.title)
                    .font(.system(size: 36, weight: .bold))
                metadataRow
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, minHeight: 340, maxHeight: 440)
    }

    private var metadataRow: some View {
        HStack(spacing: 10) {
            if let year = viewModel.yearText { Text(year) }
            if let runtime = viewModel.runtimeText { Text(runtime) }
            if let contentRating = viewModel.media.contentRating { Text(contentRating) }
            if let rating = viewModel.ratingText {
                Label(rating, systemImage: "star.fill").foregroundStyle(.yellow)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
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
        HStack(spacing: 12) {
            Button {
                guard let ratingKey = viewModel.primaryActionRatingKey else { return }
                onPlay(ratingKey, viewModel.media.plexType, false, true)
            } label: {
                Label(viewModel.primaryActionTitle, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.primaryActionRatingKey == nil)

            if viewModel.shouldShowPlayFromStartButton,
               let ratingKey = viewModel.primaryActionRatingKey
            {
                Button("common.actions.playFromStart", systemImage: "backward.end.fill") {
                    onPlay(ratingKey, viewModel.media.plexType, false, false)
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
                if !viewModel.seasons.isEmpty {
                    Picker("media.detail.season", selection: seasonBinding) {
                        ForEach(viewModel.seasons) { season in
                            Text(season.title).tag(season.id)
                        }
                    }
                    .frame(width: 220)
                }
            }

            if viewModel.isLoadingSeasons || viewModel.isLoadingEpisodes {
                ProgressView()
            } else if let error = viewModel.seasonsErrorMessage ?? viewModel.episodesErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
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

    private var seasonBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedSeasonId ?? "" },
            set: { id in Task { await viewModel.selectSeason(id: id) } },
        )
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
