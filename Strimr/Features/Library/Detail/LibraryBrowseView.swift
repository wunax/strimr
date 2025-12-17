import SwiftUI

struct LibraryBrowseView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaItem) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 100, maximum: 180), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(viewModel.items) { media in
                    PortraitMediaCard(media: media) {
                        onSelectMedia(media)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
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
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("library.browse.loading")
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle.fill", description: Text("common.errors.tryAgainLater"))
                    .symbolRenderingMode(.multicolor)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("library.browse.empty.title", systemImage: "square.grid.2x2.fill", description: Text("library.browse.empty.description"))
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

#Preview {
    let context = PlexAPIContext()
    let viewModel = LibraryBrowseViewModel(
        library: Library(id: "1", title: "Movies", type: .movie, sectionId: 1),
        context: context
    )
    viewModel.items = []

    return LibraryBrowseView(
        viewModel: viewModel,
        onSelectMedia: { _ in }
    )
    .environment(context)
}
