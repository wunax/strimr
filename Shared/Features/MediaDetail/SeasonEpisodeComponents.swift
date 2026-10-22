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
                .font(.subheadline)
        } else if viewModel.isLoadingSeasons || viewModel.isLoading, viewModel.seasons.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("media.detail.loadingSeasons")
                    .font(.subheadline)
                    .foregroundStyle(.textSecondary)
            }
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasons")
                .font(.subheadline)
                .foregroundStyle(.textSecondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.seasons) { season in
                        SeasonPill(title: season.title, isSelected: season.id == viewModel.selectedSeasonId) {
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

/// White once selected, like the play button and the tvOS season chips.
struct SeasonPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.facts.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.black : .textPrimary)
                .background(isSelected ? Color.white : .surfaceRaised, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
            #if os(macOS)
                .hoverLift(scale: 1.04)
            #endif
                .animation(Motion.crossfade, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        VStack(alignment: .leading, spacing: 4) {
            if !eyebrow.isEmpty {
                Text(eyebrow)
                    .eyebrowStyle()
                    .foregroundStyle(.textTertiary)
                    .lineLimit(1)
            }

            Text(episode.title)
                .font(.headline)
                .foregroundStyle(.textPrimary)
                .lineLimit(1)

            Group {
                if episode.shouldHideSpoilerSummary(at: settingsManager.interface.spoilerProtection) {
                    Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
                } else if let summary = episode.summary, !summary.isEmpty {
                    Text(summary)
                }
            }
            .font(.callout)
            .foregroundStyle(.textSecondary)
            .lineLimit(summaryLineLimit)
            .padding(.top, 2)
        }
    }

    private var eyebrow: String {
        [episode.tertiaryLabel, runtime].compactMap(\.self).joined(separator: " · ")
    }
}
