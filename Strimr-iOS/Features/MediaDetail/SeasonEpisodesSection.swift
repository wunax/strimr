import Observation
import SwiftUI

struct SeasonEpisodesSection: View {
    @Bindable var viewModel: MediaDetailViewModel
    let onSelectSeason: (MediaItem) -> Void
    let onSelectEpisode: (MediaItem) -> Void

    var body: some View {
        Section {
            sectionContent
        }
        .textCase(nil)
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.media.type == .show {
                    seasonSelector
                }
                episodesCountTitle
                episodesContent
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private var episodesCountTitle: some View {
        Text("media.labels.countEpisode \(viewModel.episodes.count)")
            .font(.headline)
            .fontWeight(.semibold)
    }

    @ViewBuilder
    private var seasonSelector: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        } else if viewModel.isLoadingSeasons || viewModel.isLoading, viewModel.seasons.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("media.detail.loadingSeasons")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasons")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.seasons) { season in
                        Button {
                            if season.id == viewModel.selectedSeasonId {
                                onSelectSeason(season)
                            } else {
                                Task { await viewModel.selectSeason(id: season.id) }
                            }
                        } label: {
                            Text(season.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundStyle(
                                    season.id == viewModel.selectedSeasonId
                                        ? Color.brandSecondaryForeground
                                        : Color.primary,
                                )
                                .background {
                                    Capsule()
                                        .fill(
                                            season.id == viewModel.selectedSeasonId
                                                ? Color.brandSecondary
                                                : Color.brandSecondary.opacity(0.12),
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            season.id == viewModel.selectedSeasonId ? .isSelected : [],
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var episodesContent: some View {
        if viewModel.media.type == .show, let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(.vertical, 8)
        } else if viewModel.media.type == .show,
                  viewModel.isLoadingSeasons || viewModel.isLoading,
                  viewModel.seasons.isEmpty
        {
            ProgressView("media.detail.loadingSeasons")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if viewModel.media.type == .show, viewModel.seasons.isEmpty {
            Text("media.detail.noSeasonsYet")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let error = viewModel.episodesErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
                    ProgressView("media.detail.loadingEpisodes")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if viewModel.episodes.isEmpty {
                    Text("media.detail.noEpisodes")
                        .foregroundStyle(.secondary)
                } else {
                    episodeList
                }
            }
        }
    }

    private var episodeList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                EpisodeCardView(
                    episode: episode,
                    imageURL: viewModel.imageURL(for: episode, width: 640, height: 360),
                    runtime: viewModel.runtimeText(for: episode),
                    progress: viewModel.progressFraction(for: episode),
                    onSelect: { onSelectEpisode(episode) },
                )
                if index < viewModel.episodes.count - 1 {
                    Divider()
                        .background(.brandSecondary)
                        .padding(.vertical, 4)
                }
            }
        }
    }
}
