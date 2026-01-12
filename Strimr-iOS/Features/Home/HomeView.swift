import SwiftUI

@MainActor
struct HomeView: View {
    @State var viewModel: HomeViewModel
    let onSelectMedia: (MediaItem) -> Void

    init(
        viewModel: HomeViewModel,
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let hub = viewModel.continueWatching, hub.hasItems {
                    MediaHubSection(title: hub.title) {
                        MediaCarousel(
                            layout: .landscape,
                            items: hub.items,
                            showsLabels: true,
                            onSelectMedia: onSelectMedia,
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
                                    showsLabels: true,
                                    onSelectMedia: onSelectMedia,
                                )
                            }
                        }
                    }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle("tabs.home")
        .navigationBarTitleDisplayMode(.inline)
        .userMenuToolbar()
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.reload()
        }
    }
}
