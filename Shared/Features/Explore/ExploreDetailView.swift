import SwiftUI

/// A catalog title. With Seerr connected and a TMDB id known, the Seerr page shows it, with the libraries and the
/// watchlist added; otherwise this page does.
struct ExploreDetailView: View {
    @Environment(SeerrStore.self) private var seerrStore
    @Environment(SettingsManager.self) private var settingsManager
    @State private var viewModel: ExploreDetailViewModel
    let onSelectItem: (ExploreItem) -> Void
    let onSelectSeerrMedia: (SeerrMedia) -> Void
    let onSelectCopy: (MediaItem) -> Void

    init(
        viewModel: ExploreDetailViewModel,
        onSelectItem: @escaping (ExploreItem) -> Void,
        onSelectSeerrMedia: @escaping (SeerrMedia) -> Void,
        onSelectCopy: @escaping (MediaItem) -> Void,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectItem = onSelectItem
        self.onSelectSeerrMedia = onSelectSeerrMedia
        self.onSelectCopy = onSelectCopy
    }

    var body: some View {
        Group {
            if let media = viewModel.seerrMedia {
                seerrPage(media)
            } else if viewModel.needsDetailBeforeSeerr {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                catalogPage
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private func seerrPage(_ media: SeerrMedia) -> some View {
        #if os(tvOS)
            SeerrMediaDetailView(
                viewModel: SeerrMediaDetailViewModel(media: media, store: seerrStore),
                explore: viewModel,
            )
        #else
            SeerrMediaDetailView(
                viewModel: SeerrMediaDetailViewModel(media: media, store: seerrStore),
                explore: viewModel,
                onSelectMedia: onSelectSeerrMedia,
                onSelectCopy: onSelectCopy,
            )
        #endif
    }

    #if os(tvOS)
        /// Laid out like the Seerr page: the backdrop fills the screen and the sections scroll over it.
        private var catalogPage: some View {
            GeometryReader { proxy in
                ZStack {
                    ExploreHeroBackgroundView(item: viewModel.item)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            ExploreHeroContentView(item: viewModel.item)
                                .frame(maxWidth: proxy.size.width * 0.60, alignment: .leading)

                            HStack(spacing: 16) {
                                ExploreWatchlistButton(viewModel: viewModel)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .focusSection()

                            ExploreLibrarySection(viewModel: viewModel, onSelectCopy: onSelectCopy)
                                .padding(.trailing, LayoutMetrics.pageMargin)

                            if !viewModel.related.isEmpty {
                                MediaHubSection(title: String(localized: "explore.detail.related")) {
                                    ExploreCarousel(
                                        items: viewModel.related,
                                        showsLabels: settingsManager.interface.showsCardLabels,
                                        onSelect: onSelectItem,
                                    )
                                }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .toolbar(.hidden, for: .tabBar)
        }
    #else
        private var catalogPage: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    header

                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        ExploreWatchlistButton(viewModel: viewModel)

                        if let overview = viewModel.item.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.bodyText)
                                .foregroundStyle(.textSecondary)
                                .frame(maxWidth: 900, alignment: .leading)
                        }

                        ExploreLibrarySection(viewModel: viewModel, onSelectCopy: onSelectCopy)

                        if !viewModel.related.isEmpty {
                            MediaHubSection(title: String(localized: "explore.detail.related")) {
                                ExploreCarousel(
                                    items: viewModel.related,
                                    showsLabels: settingsManager.interface.showsCardLabels,
                                    onSelect: onSelectItem,
                                )
                            }
                        }
                    }
                    .padding(.horizontal, LayoutMetrics.pageMargin)
                }
                .padding(.bottom, 32)
            }
            #if os(iOS)
            .ignoresSafeArea(edges: .top)
            #elseif os(macOS)
            .navigationTitle(viewModel.item.title)
            #endif
        }

        private var header: some View {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)
                    .overlay {
                        AsyncImage(url: viewModel.item.backdropURL ?? viewModel.item.posterURL) { phase in
                            if case let .success(image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.surfaceSubtle
                            }
                        }
                    }
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [.clear, Color("Background")],
                            startPoint: .center,
                            endPoint: .bottom,
                        )
                    }

                HStack(alignment: .bottom, spacing: 20) {
                    ExploreItemArtworkView(item: viewModel.item, width: posterWidth, height: posterWidth * 1.5)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.item.title)
                            .font(.heroTitle)
                            .foregroundStyle(.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        HStack(spacing: 12) {
                            MediaTypeBadge(type: viewModel.item.kind.mediaKind)
                            if let year = viewModel.item.year {
                                Text(String(year))
                                    .font(.facts)
                                    .foregroundStyle(.textSecondary)
                            }
                            Label(viewModel.item.source.displayName, systemImage: viewModel.item.source.systemImage)
                                .font(.facts)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, LayoutMetrics.pageMargin)
            }
        }

        private var heroHeight: CGFloat {
            #if os(macOS)
                360
            #else
                420
            #endif
        }

        private let posterWidth: CGFloat = 110
        private let sectionSpacing: CGFloat = 20
    #endif
}
