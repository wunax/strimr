import SwiftUI

struct LibraryBrowseView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 112, maximum: 112), spacing: 12),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.hasDisplayTypes {
                    LibraryBrowseControlsView(viewModel: viewModel)
                        .padding(.horizontal, 16)
                }

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(Array(viewModel.browseItems.enumerated()), id: \.element.id) { index, item in
                        Group {
                            switch item {
                            case let .media(media):
                                PortraitMediaCard(media: media, width: 112, showsLabels: true) {
                                    onSelectMedia(media)
                                }
                            case let .folder(folder):
                                FolderCard(title: folder.title, width: 112, showsLabels: true) {
                                    viewModel.enterFolder(folder)
                                }
                            }
                        }
                        .task {
                            if index == viewModel.browseItems.count - 1 {
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
            }
            .padding(.top, 16)
        }
        .overlay {
            if viewModel.isLoading, viewModel.browseItems.isEmpty {
                ProgressView("library.browse.loading")
            } else if let errorMessage = viewModel.errorMessage, viewModel.browseItems.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater"),
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.browseItems.isEmpty {
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
    }
}
