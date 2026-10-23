import Observation
import SwiftUI

struct SeerrMediaDetailView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @State var viewModel: SeerrMediaDetailViewModel
    @State private var requestSheet: SeerrMediaRequestSheetState?
    @State private var manageRequestsSheet: SeerrManageRequestsSheetState?

    init(viewModel: SeerrMediaDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        GeometryReader { proxy in
            ZStack {
                SeerrHeroBackgroundView(media: bindableViewModel.media)

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        SeerrHeroContentView(
                            media: bindableViewModel.media,
                            ratings: bindableViewModel.ratings,
                            isDownloading: bindableViewModel.isDownloading,
                        )
                        .frame(maxWidth: proxy.size.width * 0.60, alignment: .leading)

                        actionButtons

                        if let errorMessage = bindableViewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        } else if bindableViewModel.isLoading {
                            ProgressView("media.detail.updating")
                        }

                        if bindableViewModel.media.mediaType == .tv {
                            seasonsSection
                        }

                        SeerrCastSection(viewModel: bindableViewModel)

                        SeerrCollectionSection(
                            viewModel: bindableViewModel,
                            onSelectMedia: coordinator.showSeerrMediaDetail,
                        )

                        SeerrRelatedSection(
                            viewModel: bindableViewModel,
                            section: .recommendations,
                            onSelectMedia: coordinator.showSeerrMediaDetail,
                        )

                        SeerrRelatedSection(
                            viewModel: bindableViewModel,
                            section: .similar,
                            onSelectMedia: coordinator.showSeerrMediaDetail,
                        )
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .task {
            await viewModel.loadDetails()
            async let ratings: Void = viewModel.loadRatings()
            async let collection: Void = viewModel.loadCollection()
            _ = await (ratings, collection)
            await viewModel.loadRelatedContent()
        }
        .toolbar(.hidden, for: .tabBar)
        .taskPresentation(
            item: $requestSheet,
            style: viewModel.media.mediaType == .tv ? .modal : .compactModal,
        ) { sheet in
            SeerrMediaRequestView(viewModel: sheet.viewModel, onComplete: reloadAfterRequestChange)
        }
        .taskPresentation(item: $manageRequestsSheet) { sheet in
            SeerrManageRequestsView(viewModel: sheet.viewModel, onComplete: reloadAfterRequestChange)
        }
    }

    private func reloadAfterRequestChange() {
        Task {
            await viewModel.loadDetails()
            await viewModel.loadRelatedContent()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            if !viewModel.isRequestButtonHidden,
               let requestViewModel = viewModel.makeRequestViewModel()
            {
                Button {
                    requestSheet = SeerrMediaRequestSheetState(viewModel: requestViewModel)
                } label: {
                    Label(LocalizedStringKey(viewModel.requestButtonTitleKey), systemImage: requestButtonIcon)
                        .font(.facts.weight(.semibold))
                        .padding(.horizontal, 12)
                }
                .actionButtonStyle(.primary)
            }

            if viewModel.shouldShowManageRequestsButton,
               let manageViewModel = viewModel.makeManageRequestsViewModel()
            {
                Button {
                    manageRequestsSheet = SeerrManageRequestsSheetState(viewModel: manageViewModel)
                } label: {
                    Label(
                        String(localized: "seerr.manageRequests.short \(viewModel.pendingManageRequestsCount)"),
                        systemImage: "checkmark.seal.fill",
                    )
                    .font(.facts.weight(.semibold))
                    .padding(.horizontal, 12)
                }
                .actionButtonStyle(.secondary)
            }
        }
        // Full width so moving up from the right side of a rail below still lands on an action.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var requestButtonIcon: String {
        viewModel.pendingRequest == nil ? "paperplane.fill" : "square.and.pencil"
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
                    .foregroundStyle(.textSecondary)
            }
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasons")
                .foregroundStyle(.textSecondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutMetrics.chipSpacing) {
                    ForEach(viewModel.seasons) { season in
                        SeasonPillButton(
                            title: viewModel.seasonTitle(for: season),
                            isSelected: season.seasonNumber == viewModel.selectedSeasonNumber,
                            onSelect: {
                                guard let number = season.seasonNumber else { return }
                                Task { await viewModel.selectSeason(number: number) }
                            },
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }

    @ViewBuilder
    private var episodesRow: some View {
        if let error = viewModel.episodesErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
            HStack(alignment: .top, spacing: episodeSpacing) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    EpisodeSkeletonCard(width: episodeWidth)
                }
            }
            .padding(.vertical, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("media.detail.loadingEpisodes"))
        } else if viewModel.episodes.isEmpty {
            Text("media.detail.noEpisodes")
                .foregroundStyle(.textSecondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: episodeSpacing) {
                    ForEach(viewModel.episodes) { episode in
                        SeerrEpisodeRailCard(
                            episode: episode,
                            imageURL: viewModel.episodeImageURL(for: episode, width: 640),
                            label: viewModel.episodeLabel(for: episode),
                            airDateText: viewModel.episodeAirDateText(for: episode),
                            width: episodeWidth,
                        )
                    }
                }
                .padding(.vertical, 16)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }

    private let episodeWidth: CGFloat = 460
    private let episodeSpacing: CGFloat = 36
}

/// Episode of a series that is not in the library yet: artwork and caption like the library episode rail, without
/// any action.
private struct SeerrEpisodeRailCard: View {
    let episode: SeerrEpisode
    let imageURL: URL?
    let label: String?
    let airDateText: String?
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            artwork
            caption
        }
        .frame(width: width, alignment: .leading)
    }

    private var height: CGFloat {
        width * 9 / 16
    }

    private var artwork: some View {
        AsyncImage(url: imageURL) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Color.surfaceSubtle
            }
        }
        .frame(width: width, height: height)
        .mediaArtworkStyle()
        .focusable()
        .focused($isFocused)
        .cardFocusStyle(isFocused: isFocused)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([label, airDateText].compactMap(\.self).joined(separator: " · "))
                .eyebrowStyle()
                .foregroundStyle(.textTertiary)
                .opacity(isFocused ? 1 : 0.32 / 0.45)
                .lineLimit(1)
            Text(title)
                .font(.cardTitle)
                .foregroundStyle(.textPrimary.opacity(isFocused ? 1 : 0.45))
                .lineLimit(1)
        }
        // Follows the bottom edge of the focused artwork so the lifted card does not cover its caption.
        .offset(y: isFocused && !reduceMotion ? height * (CardFocusStyle.focusedScale - 1) / 2 : 0)
        .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isFocused)
    }

    private var title: String {
        if let name = episode.name, !name.isEmpty {
            return name
        }
        return episode.episodeNumber.map { String(localized: "media.detail.episodeNumber \($0)") } ?? ""
    }
}

private struct SeerrMediaRequestSheetState: Identifiable {
    let id = UUID()
    let viewModel: SeerrMediaRequestViewModel
}

private struct SeerrManageRequestsSheetState: Identifiable {
    let id = UUID()
    let viewModel: SeerrManageRequestsViewModel
}
