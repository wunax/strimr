import Observation
import SwiftUI

struct SeasonEpisodesSection: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Bindable var viewModel: MediaDetailViewModel
    let onSelectSeason: (MediaItem) -> Void
    let onSelectEpisode: (MediaItem) -> Void

    var body: some View {
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
                        SeasonPillsRow(viewModel: viewModel, onSelectSeason: onSelectSeason)
                    }
                    episodesContent
                }
            }
        }
        .padding(.horizontal, LayoutMetrics.detailSectionMargin)
        .padding(.bottom, 32)
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if viewModel.episodes.isEmpty {
            Text("media.detail.noEpisodes")
                .font(.facts)
                .foregroundStyle(.textSecondary)
        } else {
            episodeList
        }
    }

    private var episodeList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                EpisodeCardView(
                    episode: episode,
                    imageURL: viewModel.imageURL(
                        for: episode,
                        width: 640,
                        height: 360,
                        spoilerProtection: settingsManager.interface.spoilerProtection,
                    ),
                    runtime: viewModel.runtimeText(for: episode),
                    progress: viewModel.progressFraction(for: episode),
                    onSelect: { onSelectEpisode(episode) },
                )
                if index < viewModel.episodes.count - 1 {
                    Divider()
                }
            }
        }
    }
}
