import SwiftUI

/// Season chips of the iOS and macOS detail pages, with their loading and error states. Tapping the selected season
/// opens it.
struct SeasonPillsRow: View {
    @Bindable var viewModel: MediaDetailViewModel
    let onSelectSeason: (MediaItem) -> Void

    var body: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.facts)
        } else if viewModel.isLoadingSeasons || viewModel.isLoading, viewModel.seasons.isEmpty {
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
                        FilterChip(title: season.title, isSelected: season.id == viewModel.selectedSeasonId) {
                            if season.id == viewModel.selectedSeasonId {
                                onSelectSeason(season)
                            } else {
                                Task { await viewModel.selectSeason(id: season.id) }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .mouseDragScrolling()
        }
    }
}

/// Episode number and runtime over the title, as in the tvOS episode rail, then the summary unless it is hidden
/// against spoilers.
struct EpisodeRowText: View {
    @Environment(SettingsManager.self) private var settingsManager
    let episode: MediaItem
    let runtime: String?
    var summaryLineLimit = 3

    var body: some View {
        EpisodeCaption(
            eyebrow: [episode.tertiaryLabel, runtime].compactMap(\.self).joined(separator: " · "),
            title: episode.title,
            summaryLineLimit: summaryLineLimit,
        ) {
            if episode.shouldHideSpoilerSummary(at: settingsManager.interface.spoilerProtection) {
                Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
            } else if let summary = episode.summary, !summary.isEmpty {
                Text(summary)
            }
        }
    }
}

/// Text block of an episode row: a small uppercase line over the title, then the summary.
struct EpisodeCaption<Summary: View>: View {
    let eyebrow: String
    let title: String
    var summaryLineLimit = 3
    @ViewBuilder let summary: Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !eyebrow.isEmpty {
                Text(eyebrow)
                    .eyebrowStyle()
                    .foregroundStyle(.textTertiary)
                    .lineLimit(1)
            }

            Text(title)
                .font(.rowTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(1)

            summary
                .font(.facts)
                .foregroundStyle(.textSecondary)
                .lineLimit(summaryLineLimit)
                .padding(.top, 2)
        }
    }
}
