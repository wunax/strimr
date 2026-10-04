import SwiftUI

struct LibraryPlaylistsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.scenePhase) private var scenePhase
    @State var viewModel: LibraryPlaylistsViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private var cardWidth: CGFloat {
        settingsManager.interface.posterSize.gridCardWidth
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12),
        ]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(viewModel.items) { media in
                    PortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                        onSelectMedia(media)
                    }
                    .task {
                        if media == viewModel.items.last {
                            await viewModel.loadMore()
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
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
