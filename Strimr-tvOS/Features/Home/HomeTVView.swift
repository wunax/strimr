import SwiftUI

@MainActor
struct HomeTVView: View {
    @Environment(MediaFocusModel.self) private var focusModel

    @State var viewModel: HomeViewModel
    let onSelectMedia: (MediaItem) -> Void

    init(
        viewModel: HomeViewModel,
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            if let heroMedia {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        ZStack(alignment: .topLeading) {
                            MediaHeroBackgroundView(media: focusModel.focusedMedia ?? heroMedia)
                            MediaHeroContentView(media: focusModel.focusedMedia ?? heroMedia)
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
        .onChange(of: heroMedia?.id) { _, _ in
            updateInitialFocus()
        }
        .onAppear {
            updateInitialFocus()
        }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let hub = viewModel.continueWatching, hub.hasItems {
                    MediaHubSection(title: hub.title) {
                        MediaCarousel(
                            layout: .landscape,
                            items: hub.items,
                            showsLabels: false,
                            onSelectMedia: onSelectMedia
                        )
                    }
                }

                if !viewModel.recentlyAdded.isEmpty {
                    ForEach(viewModel.recentlyAdded) { hub in
                        if hub.hasItems {
                            MediaHubSection(title: hub.title) {
                                MediaCarousel(
                                    layout: .portrait,
                                    items: hub.items,
                                    showsLabels: false,
                                    onSelectMedia: onSelectMedia
                                )
                            }
                        }
                    }
                }

                if viewModel.isLoading && !viewModel.hasContent {
                    ProgressView("home.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent && !viewModel.isLoading {
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
        if let continueItem = viewModel.continueWatching?.items.first {
            return continueItem
        }

        for hub in viewModel.recentlyAdded where hub.hasItems {
            if let item = hub.items.first {
                return item
            }
        }

        return nil
    }

    private func updateInitialFocus() {
        guard focusModel.focusedMedia == nil, let heroMedia else { return }
        focusModel.focusedMedia = heroMedia
    }
}
