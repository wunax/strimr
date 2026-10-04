import SwiftUI

struct LibraryPlaylistsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State var viewModel: LibraryPlaylistsViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: LibraryPlaylistsViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            PosterGrid(spacing: 32, rowSpacing: 32) { cardWidth in
                ForEach(viewModel.items) { media in
                    PortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                        onSelectMedia(media)
                    }
                    .onAppear {
                        Task {
                            if media == viewModel.items.last {
                                await viewModel.loadMore()
                            }
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .overlay {
            if viewModel.isLoading, viewModel.items.isEmpty {
                ProgressView("library.browse.loading")
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater"),
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "library.browse.empty.title",
                    systemImage: "square.grid.2x2.fill",
                    description: Text("library.browse.empty.description"),
                )
            }
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }
}
