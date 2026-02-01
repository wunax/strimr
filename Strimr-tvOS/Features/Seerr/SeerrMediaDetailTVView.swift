import Observation
import SwiftUI

struct SeerrMediaDetailTVView: View {
    @State var viewModel: SeerrMediaDetailViewModel

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
                        SeerrHeroContentView(media: bindableViewModel.media)
                            .frame(maxWidth: proxy.size.width * 0.60, alignment: .leading)

                        actionButtons

                        if let errorMessage = bindableViewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        } else if bindableViewModel.isLoading {
                            ProgressView("media.detail.updating")
                        }

                        if bindableViewModel.media.mediaType == .tv {
                            seasonsSection(width: proxy.size.width)
                        }

                        SeerrCastSection(viewModel: bindableViewModel)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .task {
            await viewModel.loadDetails()
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            if !viewModel.isRequestButtonHidden,
               let requestViewModel = viewModel.makeRequestViewModel() {
                NavigationLink {
                    SeerrMediaRequestTVView(viewModel: requestViewModel) {
                        Task {
                            await viewModel.loadDetails()
                        }
                    }
                } label: {
                    Label(LocalizedStringKey(viewModel.requestButtonTitleKey), systemImage: requestButtonIcon)
                        .frame(maxWidth: 520, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.brandPrimary)
            }

            if viewModel.shouldShowManageRequestsButton,
               let manageViewModel = viewModel.makeManageRequestsViewModel() {
                NavigationLink {
                    SeerrManageRequestsTVView(viewModel: manageViewModel) {
                        Task {
                            await viewModel.loadDetails()
                        }
                    }
                } label: {
                    Label(
                        String(localized: "seerr.manageRequests.short \(viewModel.pendingManageRequestsCount)"),
                        systemImage: "checkmark.seal.fill"
                    )
                    .frame(maxWidth: 360, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.secondary)
            }
        }
    }

    private var requestButtonIcon: String {
        viewModel.pendingRequest == nil ? "paperplane.fill" : "square.and.pencil"
    }

    private func seasonsSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            seasonSelector
            episodesSection(width: width)
        }
    }

    @ViewBuilder
    private var seasonSelector: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if (viewModel.isLoadingSeasons || viewModel.isLoading), viewModel.seasons.isEmpty {
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
                HStack(spacing: 16) {
                    ForEach(viewModel.seasons) { season in
                        SeerrSeasonPillButton(
                            title: viewModel.seasonTitle(for: season),
                            subtitle: episodeCountTitle(for: season),
                            isSelected: season.seasonNumber == viewModel.selectedSeasonNumber,
                            onSelect: {
                                toggleSeasonSelection(season)
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .focusSection()
        }
    }

    @ViewBuilder
    private func episodesSection(width: CGFloat) -> some View {
        if viewModel.selectedSeasonNumber == nil {
            Text("seerr.detail.selectSeason")
                .foregroundStyle(.secondary)
        } else if let error = viewModel.episodesErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
            ProgressView("media.detail.loadingEpisodes")
        } else if viewModel.episodes.isEmpty {
            Text("media.detail.noEpisodes")
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: episodeGridColumns(for: width), alignment: .leading, spacing: 32) {
                ForEach(viewModel.episodes) { episode in
                    SeerrEpisodeGridCard(
                        episode: episode,
                        imageURL: viewModel.episodeImageURL(for: episode, width: 640),
                        label: viewModel.episodeLabel(for: episode),
                        airDateText: viewModel.episodeAirDateText(for: episode),
                    )
                }
            }
            .padding(.vertical, 8)
            .focusSection()
        }
    }

    private func episodeGridColumns(for width: CGFloat) -> [GridItem] {
        let columnCount = width >= 1700 ? 3 : 2
        return Array(
            repeating: GridItem(.flexible(minimum: 320), spacing: 32),
            count: columnCount
        )
    }

    private func toggleSeasonSelection(_ season: SeerrSeason) {
        guard let seasonNumber = season.seasonNumber else { return }
        if viewModel.selectedSeasonNumber == seasonNumber {
            viewModel.selectedSeasonNumber = nil
            viewModel.episodes = []
            viewModel.episodesErrorMessage = nil
        } else {
            Task { await viewModel.selectSeason(number: seasonNumber) }
        }
    }

    private func episodeCountTitle(for season: SeerrSeason) -> String? {
        let count = season.episodeCount ?? 0
        guard count > 0 else { return nil }
        let countTitle = String(localized: "media.labels.countEpisode \(count)")
        return "(\(countTitle))"
    }
}

private struct SeerrSeasonPillButton: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let onSelect: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(.brandSecondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.brandSecondary.opacity(0.5) : Color.gray.opacity(0.12))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        isFocused ? Color.brandSecondary : Color.gray.opacity(0.25),
                        lineWidth: isFocused ? 3 : 1
                    )
            }
        }
        .focusable()
        .focused($isFocused)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onPlayPauseCommand(perform: onSelect)
        .onTapGesture(perform: onSelect)
    }
}

private struct SeerrEpisodeGridCard: View {
    let episode: SeerrEpisode
    let imageURL: URL?
    let label: String?
    let airDateText: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {} label: {
            SeerrEpisodeCardView(
                episode: episode,
                imageURL: imageURL,
                label: label,
                airDateText: airDateText
            )
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
