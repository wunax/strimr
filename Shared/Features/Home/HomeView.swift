import SwiftUI

@MainActor
struct HomeView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SeerrStore.self) private var seerrStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.mediaCardActions) private var mediaCardActions
    @State var viewModel: HomeViewModel
    @State private var selectedHub: Hub?
    @State private var scrollInteractionCount = 0
    @State private var horizontalSafeArea = EdgeInsets()
    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: HomeViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            if !viewModel.heroSlides.isEmpty {
                HomeHeroCarousel(
                    slides: viewModel.heroSlides,
                    interactionCount: scrollInteractionCount,
                    horizontalSafeArea: horizontalSafeArea,
                    onPlay: { mediaCardActions?.play($0, false) },
                    onDetails: { onSelectMedia(.playable($0)) },
                )
            }

            VStack(alignment: .leading, spacing: 24) {
                ForEach(viewModel.rows) { row in
                    HomeRowSectionView(
                        row: row,
                        showsLabels: settingsManager.interface.showsCardLabels,
                        onViewAll: { selectedHub = $0 },
                        onSelectMedia: onSelectMedia,
                    )
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    RailsSkeleton(showsLabels: settingsManager.interface.showsCardLabels)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, LayoutMetrics.pageMargin)
            .padding(.vertical, 20)
        }
        .onScrollPhaseChange { _, phase in
            if phase != .idle {
                scrollInteractionCount += 1
            }
        }
        .onGeometryChange(for: EdgeInsets.self) {
            EdgeInsets(top: 0, leading: $0.safeAreaInsets.leading, bottom: 0, trailing: $0.safeAreaInsets.trailing)
        } action: {
            horizontalSafeArea = $0
        }
        #if os(iOS)
        // The hero artwork runs up behind the status and navigation bars.
        .ignoresSafeArea(edges: viewModel.heroSlides.isEmpty ? [] : .top)
        .softTopScrollEdge()
        #endif
        .navigationTitle("tabs.home")
        .tabRootChrome()
        .environment(\.reloadAfterPlaylistChange) { server in
            Task { await viewModel.refresh(server: server) }
        }
        .task {
            await viewModel.load()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await viewModel.refreshPeriodically()
        }
        .task(id: seerrStore.isLoggedIn) {
            viewModel.seerrBaseURL = seerrStore.isLoggedIn ? seerrStore.baseURLString.flatMap(URL.init(string:)) : nil
        }
        .onChange(of: settingsManager.interface.homeHero) {
            viewModel.heroSettingsChanged()
        }
        .onChange(of: settingsManager.interface.homeHeroIncludesTrending) {
            viewModel.heroSettingsChanged()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        .refreshable {
            await viewModel.reload()
        }
        .sheet(item: $selectedHub) { hub in
            NavigationStack {
                ServerScopedView(server: hub.server) { services in
                    HubDetailView(
                        viewModel: HubDetailViewModel(hub: hub, services: services),
                        onSelectMedia: { media in
                            selectedHub = nil
                            onSelectMedia(media)
                        },
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("hub.close") {
                            selectedHub = nil
                        }
                    }
                }
            }
        }
        .onChange(of: viewModel.contentRevisions) {
            viewModel.refreshAfterContentChanges()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }
}

#if os(iOS)
    private extension View {
        @ViewBuilder
        func softTopScrollEdge() -> some View {
            if #available(iOS 26.0, *) {
                scrollEdgeEffectStyle(.soft, for: .top)
            } else {
                self
            }
        }
    }
#endif
