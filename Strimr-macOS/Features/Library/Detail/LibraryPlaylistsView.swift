import SwiftUI

struct LibraryPlaylistsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(MediaServices.self) private var mediaServices: MediaServices?
    @State var viewModel: LibraryPlaylistsViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    var body: some View {
        ScrollView {
            PosterGrid(spacing: 12, rowSpacing: 16) { cardWidth in
                ForEach(viewModel.items) { media in
                    PortraitMediaCard(
                        media: media,
                        width: cardWidth,
                        showsLabels: settingsManager.interface.showsCardLabels,
                    ) {
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
        .onChange(of: mediaServices?.playlistsRevision) {
            Task { await viewModel.refresh() }
        }
    }
}
