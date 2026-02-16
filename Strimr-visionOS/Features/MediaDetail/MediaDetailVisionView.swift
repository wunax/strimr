import Observation
import SwiftUI

struct MediaDetailVisionView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(SharePlayViewModel.self) private var sharePlayViewModel
    @State var viewModel: MediaDetailViewModel
    private let onPlay: (String, PlexItemType) -> Void
    private let onPlayFromStart: (String, PlexItemType) -> Void
    private let onShuffle: (String, PlexItemType) -> Void
    private let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onPlayFromStart: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onShuffle: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onPlayFromStart = onPlayFromStart
        self.onShuffle = onShuffle
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                heroSection

                buttonsRow

                if bindableViewModel.media.type == .show {
                    seasonsSection
                }

                CastSection(viewModel: bindableViewModel)
                RelatedHubsSection(viewModel: bindableViewModel, onSelectMedia: onSelectMedia)
            }
            .padding(24)
        }
        .task {
            await bindableViewModel.loadDetails()
        }
        .onAppear {
            // Reload details when returning from player
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 24) {
            AsyncImage(url: viewModel.heroImageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
            }
            .frame(width: 560, height: 315)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.media.title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)

                Text(viewModel.media.mediaItem.primaryLabel)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let summary = viewModel.media.mediaItem.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var buttonsRow: some View {
        HStack(spacing: 16) {
            playButton

            if viewModel.shouldShowPlayFromStartButton {
                playFromStartButton
            }

            shuffleButton
            watchToggleButton

            if viewModel.shouldShowWatchlistButton {
                watchlistToggleButton
            }

            sharePlayButton
        }
    }

    private var playButton: some View {
        Button(action: handlePlay) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.primaryActionTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                    if let detail = viewModel.primaryActionDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 400, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
        .tint(.brandSecondary)
        .foregroundStyle(.brandSecondaryForeground)
    }

    private var playFromStartButton: some View {
        Button(action: handlePlayFromStart) {
            Image(systemName: "arrow.counterclockwise")
                .font(.title2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel(Text("media.detail.playFromStart"))
    }

    private var shuffleButton: some View {
        Button(action: handleShuffle) {
            Image(systemName: "shuffle")
                .font(.title2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel(Text("common.actions.shuffle"))
    }

    private var watchToggleButton: some View {
        Button {
            Task {
                await viewModel.toggleWatchStatus()
            }
        } label: {
            if viewModel.isUpdatingWatchStatus {
                ProgressView()
            } else {
                Image(systemName: viewModel.watchActionIcon)
                    .font(.title2.weight(.semibold))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus)
    }

    private var watchlistToggleButton: some View {
        Button {
            Task {
                await viewModel.toggleWatchlistStatus()
            }
        } label: {
            if viewModel.isLoadingWatchlistStatus || viewModel.isUpdatingWatchlistStatus {
                ProgressView()
            } else {
                Image(systemName: viewModel.watchlistActionIcon)
                    .font(.title2.weight(.semibold))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(viewModel.isLoading || viewModel.isLoadingWatchlistStatus || viewModel.isUpdatingWatchlistStatus)
        .accessibilityLabel(Text(viewModel.watchlistActionTitle))
    }

    private var sharePlayButton: some View {
        Button {
            sharePlayViewModel.startSharePlay(
                ratingKey: viewModel.media.id,
                type: viewModel.media.plexType,
                title: viewModel.media.title,
                thumbPath: viewModel.media.thumbPath
            )
        } label: {
            Image(systemName: "shareplay")
                .font(.title2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel(Text("SharePlay"))
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
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
                HStack(spacing: 12) {
                    ForEach(viewModel.seasons) { season in
                        Button {
                            Task { await viewModel.selectSeason(id: season.id) }
                        } label: {
                            Text(season.title)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(
                                            season.id == viewModel.selectedSeasonId
                                                ? Color.brandSecondary.opacity(0.5)
                                                : Color.secondary.opacity(0.1)
                                        ),
                                )
                                .foregroundStyle(.brandSecondary)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var episodesRow: some View {
        if let error = viewModel.episodesErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
            ProgressView("media.detail.loadingEpisodes")
        } else if viewModel.episodes.isEmpty {
            Text("media.detail.noEpisodes")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 24) {
                    ForEach(viewModel.episodes) { episode in
                        Button {
                            onPlay(episode.id, .episode)
                        } label: {
                            EpisodeArtworkView(
                                episode: episode,
                                imageURL: viewModel.imageURL(for: episode, width: 640, height: 360),
                                width: 360,
                                runtime: viewModel.runtimeText(for: episode),
                                progress: viewModel.progressFraction(for: episode),
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func handlePlay() {
        Task {
            guard let ratingKey = await viewModel.playbackRatingKey() else { return }
            onPlay(ratingKey, playbackType)
        }
    }

    private func handlePlayFromStart() {
        Task {
            guard let ratingKey = await viewModel.playbackRatingKey() else { return }
            onPlayFromStart(ratingKey, playbackType)
        }
    }

    private func handleShuffle() {
        onShuffle(viewModel.media.id, viewModel.media.plexType)
    }

    private var playbackType: PlexItemType {
        viewModel.onDeckItem?.type ?? viewModel.media.plexType
    }
}
