import Observation
import SwiftUI

struct SeerrSeasonEpisodesSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel
    @State private var expandedSeasonNumber: Int?

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
                seasonsList
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 32)
    }

    @ViewBuilder
    private var seasonsList: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .padding(.vertical, 8)
        } else if viewModel.isLoadingSeasons, viewModel.seasons.isEmpty {
            ProgressView("media.detail.loadingSeasons")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasons")
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.seasons, id: \.id) { season in
                    DisclosureGroup(
                        isExpanded: seasonExpansionBinding(for: season),
                        content: {
                            episodesContent(for: season)
                        },
                        label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(viewModel.seasonTitle(for: season))
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Text(episodeCountTitle(for: season))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let badge = viewModel.seasonAvailabilityBadge(for: season) {
                                    Spacer()
                                    SeerrSeasonAvailabilityBadgeView(badge: badge, showsLabel: true)
                                }
                            }
                        },
                    )
                    .tint(.primary)
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.brandSecondary.opacity(0.12))
                    }
                }
            }
        }
    }

    private func episodeCountTitle(for season: SeerrSeason) -> String {
        let count = season.episodeCount ?? 0
        let countTitle = String(localized: "media.labels.countEpisode \(count)")
        return "(\(countTitle))"
    }

    private func seasonExpansionBinding(for season: SeerrSeason) -> Binding<Bool> {
        Binding(
            get: {
                expandedSeasonNumber == season.seasonNumber
            },
            set: { isExpanded in
                if isExpanded {
                    expandedSeasonNumber = season.seasonNumber
                    if let seasonNumber = season.seasonNumber {
                        Task {
                            await viewModel.selectSeason(number: seasonNumber)
                        }
                    }
                } else if expandedSeasonNumber == season.seasonNumber {
                    expandedSeasonNumber = nil
                }
            },
        )
    }

    private func episodesContent(for season: SeerrSeason) -> some View {
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
            } else if season.seasonNumber == viewModel.selectedSeasonNumber {
                episodeList
            } else {
                ProgressView("media.detail.loadingEpisodes")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .padding(.top, 8)
    }

    private var episodeList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                SeerrEpisodeCardView(
                    episode: episode,
                    imageURL: viewModel.episodeImageURL(for: episode, width: 640),
                    label: viewModel.episodeLabel(for: episode),
                    airDateText: viewModel.episodeAirDateText(for: episode),
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
