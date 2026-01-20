import Observation
import SwiftUI

struct SeasonEpisodesSection: View {
    @Bindable var viewModel: MediaDetailViewModel
    let onPlay: (String) -> Void

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
                seasonSelector
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
            HStack(alignment: .center, spacing: 10) {
                seasonPickerControl
                Spacer(minLength: 0)
                seasonWatchToggle
            }
        }
    }

    @ViewBuilder
    private var seasonPickerControl: some View {
        Picker("media.detail.season", selection: Binding(
            get: { viewModel.selectedSeasonId ?? viewModel.seasons.first?.id ?? "" },
            set: { seasonId in
                guard !seasonId.isEmpty else { return }
                Task {
                    await viewModel.selectSeason(id: seasonId)
                }
            },
        )) {
            ForEach(viewModel.seasons, id: \.id) { season in
                Text(season.title)
                    .tag(season.id)
            }
        }
        .pickerStyle(.menu)
        .tint(.brandSecondaryForeground)
        .background(.brandSecondary)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var seasonWatchToggle: some View {
        if let season = viewModel.selectedSeason ?? viewModel.seasons.first {
            Button {
                Task {
                    await viewModel.toggleWatchStatus(for: season)
                }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isUpdatingWatchStatus(for: season) {
                        ProgressView()
                    } else {
                        Image(systemName: viewModel.watchActionIcon(for: season))
                    }
                    Text(viewModel.watchActionTitle(for: season))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.brandSecondary)
            .disabled(viewModel.isUpdatingWatchStatus(for: season))
        }
    }

    @ViewBuilder
    private var episodesContent: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(.vertical, 8)
        } else if viewModel.isLoadingSeasons || viewModel.isLoading, viewModel.seasons.isEmpty {
            ProgressView("media.detail.loadingSeasons")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if viewModel.seasons.isEmpty {
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

    @ViewBuilder
    private var episodeList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                EpisodeCardView(
                    episode: episode,
                    imageURL: viewModel.imageURL(for: episode, width: 640, height: 360),
                    runtime: viewModel.runtimeText(for: episode),
                    progress: viewModel.progressFraction(for: episode),
                    isWatched: viewModel.isWatched(episode),
                    isUpdatingWatchStatus: viewModel.isUpdatingWatchStatus(for: episode),
                    onToggleWatch: {
                        Task {
                            await viewModel.toggleWatchStatus(for: episode)
                        }
                    },
                    onPlay: {
                        onPlay(episode.id)
                    },
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
