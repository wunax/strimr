import Observation
import SwiftUI

/// Seasons and episodes of a series that may not be in the library yet, laid out like the library detail page.
struct SeerrSeasonEpisodesSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel

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
                    seasonPills

                    if let selectedSeason = viewModel.selectedSeason,
                       let badge = viewModel.seasonAvailabilityBadge(for: selectedSeason)
                    {
                        SeerrSeasonAvailabilityBadgeView(
                            badge: badge,
                            showsLabel: true,
                            isDownloading: viewModel.isDownloading,
                        )
                    }

                    episodesContent
                }
            }
        }
        .padding(.horizontal, LayoutMetrics.detailSectionMargin)
        .padding(.bottom, 32)
    }

    @ViewBuilder
    private var seasonPills: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.facts)
        } else if viewModel.isLoadingSeasons, viewModel.seasons.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("media.detail.loadingSeasons")
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
            }
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasons")
                .font(.facts)
                .foregroundStyle(.textSecondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutMetrics.chipSpacing) {
                    ForEach(viewModel.seasons) { season in
                        FilterChip(
                            title: viewModel.seasonTitle(for: season),
                            isSelected: season.seasonNumber == viewModel.selectedSeasonNumber,
                        ) {
                            guard let number = season.seasonNumber else { return }
                            Task { await viewModel.selectSeason(number: number) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .mouseDragScrolling()
        }
    }

    @ViewBuilder
    private var episodesContent: some View {
        if viewModel.seasons.isEmpty || viewModel.seasonsErrorMessage != nil {
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
            LazyVStack(alignment: .leading, spacing: episodeSpacing) {
                ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                    SeerrEpisodeCardView(
                        episode: episode,
                        imageURL: viewModel.episodeImageURL(for: episode, width: 640),
                        label: viewModel.episodeLabel(for: episode),
                        airDateText: viewModel.episodeAirDateText(for: episode),
                    )
                    #if os(iOS)
                        if index < viewModel.episodes.count - 1 {
                            Divider()
                        }
                    #endif
                }
            }
        }
    }

    private var episodeSpacing: CGFloat {
        #if os(macOS)
            8
        #else
            0
        #endif
    }
}
