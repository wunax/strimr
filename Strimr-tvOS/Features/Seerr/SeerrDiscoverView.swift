import SwiftUI

@MainActor
struct SeerrDiscoverView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SeerrFocusModel.self) private var focusModel
    @Environment(SeerrStore.self) private var seerrStore
    @State var viewModel: SeerrDiscoverViewModel
    let onSelectMedia: (SeerrMedia) -> Void

    init(
        viewModel: SeerrDiscoverViewModel,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            if let heroMedia {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        ZStack(alignment: .topLeading) {
                            SeerrHeroBackgroundView(media: focusModel.focusedMedia ?? heroMedia)
                            VStack(alignment: .leading, spacing: 20) {
                                SeerrHeroContentView(media: focusModel.focusedMedia ?? heroMedia)
                                heroActions
                            }
                            .frame(
                                maxWidth: proxy.size.width * 0.60,
                                maxHeight: .infinity,
                                alignment: .topLeading,
                            )
                        }

                        discoverContent
                            .frame(height: proxy.size.height * railsHeightRatio)
                    }
                }
            } else {
                emptyState
            }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: heroMedia?.id) { _, _ in
            updateInitialFocus()
        }
        .onAppear {
            updateInitialFocus()
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }

    private var heroActions: some View {
        HStack(spacing: 16) {
            NavigationLink {
                SeerrSearchView(
                    viewModel: SeerrSearchViewModel(store: seerrStore),
                    onSelectMedia: onSelectMedia,
                )
            } label: {
                Label("tabs.search", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .actionButtonStyle(.primary)

            Button {
                coordinator.showSeerrRequests()
            } label: {
                Label(
                    viewModel.requestsBadgeCount > 0
                        ? String(localized: "seerr.manageRequests.short \(viewModel.requestsBadgeCount)")
                        : String(localized: "seerr.requests.title"),
                    systemImage: "tray.full.fill",
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .actionButtonStyle(.secondary)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .focusSection()
    }

    private var discoverContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                rail(String(localized: "integrations.seerr.discover.trending"), items: viewModel.trending)
                rail(String(localized: "integrations.seerr.discover.popularMovies"), items: viewModel.popularMovies)
                rail(String(localized: "integrations.seerr.discover.upcomingMovies"), items: viewModel.upcomingMovies)
                rail(String(localized: "integrations.seerr.discover.popularTV"), items: viewModel.popularTV)
                rail(String(localized: "integrations.seerr.discover.upcomingTV"), items: viewModel.upcomingTV)

                if viewModel.isLoading, !viewModel.hasContent {
                    RailsSkeleton(showsLabels: settingsManager.interface.showsCardLabels)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.textSecondary)
                }
            }
            .padding(.trailing, LayoutMetrics.pageMargin)
        }
    }

    /// Below the 0.60 of the library home: the hero here also holds the search and requests buttons.
    private let railsHeightRatio: CGFloat = 0.54

    @ViewBuilder
    private func rail(_ title: String, items: [SeerrMedia]) -> some View {
        if !items.isEmpty {
            MediaHubSection(title: title) {
                SeerrMediaCarousel(
                    items: items,
                    showsLabels: settingsManager.interface.showsCardLabels,
                    onSelectMedia: onSelectMedia,
                )
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isLoading {
            GeometryReader { proxy in
                RailsSkeleton(showsLabels: settingsManager.interface.showsCardLabels)
                    .padding(.trailing, LayoutMetrics.pageMargin)
                    .frame(height: proxy.size.height * railsHeightRatio, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        } else {
            emptyMessage
        }
    }

    private var emptyMessage: some View {
        VStack(spacing: 16) {
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Text("common.empty.nothingToShow")
                    .foregroundStyle(.textSecondary)
            }
        }
    }

    private var heroMedia: SeerrMedia? {
        if let media = viewModel.trending.first {
            return media
        }
        if let media = viewModel.popularMovies.first {
            return media
        }
        return viewModel.popularTV.first
    }

    private func updateInitialFocus() {
        guard focusModel.focusedMedia == nil, let heroMedia else { return }
        focusModel.focusedMedia = heroMedia
    }
}
