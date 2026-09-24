import SwiftUI

@MainActor
struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(MediaFocusModel.self) private var focusModel
    @EnvironmentObject private var coordinator: MainCoordinator

    @State var viewModel: HomeViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: HomeViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            if let heroMedia = displayedHeroMedia {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        ZStack(alignment: .topLeading) {
                            MediaHeroBackgroundView(media: heroMedia)
                            MediaHeroContentView(media: heroMedia)
                                .frame(maxWidth: proxy.size.width * 0.60, maxHeight: .infinity, alignment: .topLeading)
                        }

                        homeContent
                            .frame(height: proxy.size.height * 0.60)
                    }
                }
            } else {
                emptyState
            }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: visibleHeroMediaIDs) { _, _ in
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

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ForEach(viewModel.rows) { row in
                    HomeRowSectionView(
                        row: row,
                        showsLabels: false,
                        onViewAll: coordinator.showHubDetail,
                        onSelectMedia: onSelectMedia,
                    )
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("home.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if viewModel.isLoading {
                ProgressView("home.loading")
            } else if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Text("common.empty.nothingToShow")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heroMedia: MediaItem? {
        viewModel.rows.lazy
            .flatMap { $0.items.compactMap(\.playableItem) }
            .first
    }

    private var visibleHeroMediaIDs: [String] {
        viewModel.rows.flatMap { $0.items.compactMap(\.playableItem).map(\.id) }
    }

    private var displayedHeroMedia: MediaItem? {
        if let focusedMedia = focusModel.focusedMedia,
           visibleHeroMediaIDs.contains(focusedMedia.id)
        {
            return focusedMedia
        }
        return heroMedia
    }

    private func updateInitialFocus() {
        guard let heroMedia else {
            focusModel.focusedMedia = nil
            return
        }
        guard focusModel.focusedMedia == nil || !visibleHeroMediaIDs.contains(focusModel.focusedMedia?.id ?? "") else {
            return
        }
        focusModel.focusedMedia = heroMedia
    }
}
