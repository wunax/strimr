import SwiftUI

struct LibraryBrowseView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private var downloadedOnlyToggle: LibraryBrowseToggle? {
        guard viewModel.showsDownloadedOnlyToggle else { return nil }
        return LibraryBrowseToggle(
            title: String(localized: "offline.library.downloadedOnly"),
            systemImage: "arrow.down.circle",
            isSelected: viewModel.isDownloadedOnly,
            action: viewModel.toggleDownloadedOnly,
        )
    }

    private var folderTreeToggle: LibraryBrowseToggle? {
        guard viewModel.canShowFolderTree else { return nil }
        return .folderTree(isSelected: viewModel.showsFolderTree, action: viewModel.toggleFolderTree)
    }

    @ViewBuilder
    private func browseItems(cardWidth: CGFloat? = nil) -> some View {
        ForEach(Array(viewModel.browseItems.enumerated()), id: \.element.id) { index, item in
            browseItem(item, cardWidth: cardWidth)
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

    @ViewBuilder
    private func browseItem(_ item: LibraryBrowseItem, cardWidth: CGFloat?) -> some View {
        switch (item, viewModel.layout) {
        case let (.media(media), .grid):
            PortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                onSelectMedia(media)
            }
        case let (.media(media), .list):
            MediaListRow(media: media) {
                onSelectMedia(media)
            }
        case let (.folder(folder), .grid):
            FolderCard(title: folder.title, width: cardWidth, showsLabels: true) {
                viewModel.enterFolder(folder)
            }
        case let (.folder(folder), .list):
            FolderListRow(title: folder.title) {
                viewModel.enterFolder(folder)
            }
        }
    }

    var body: some View {
        @Bindable var controls = viewModel.controls

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear
                        .frame(height: 0)
                        .id("libraryBrowseTop")

                    LibraryBrowseControlsView(
                        viewModel: controls,
                        showsBackButton: viewModel.canNavigateBack,
                        onNavigateBack: viewModel.navigateBack,
                        leadingToggle: downloadedOnlyToggle,
                        showsServerControls: viewModel.showsServerControls,
                        folderTreeToggle: folderTreeToggle,
                        layoutToggle: viewModel.folderTree == nil
                            ? .layout(current: viewModel.layout, onChange: viewModel.setLayout)
                            : nil,
                        itemCount: viewModel.folderTree == nil ? viewModel.totalCount : nil,
                    )
                    .padding(.horizontal, 16)

                    Group {
                        if let folderTree = viewModel.folderTree {
                            FolderTreeView(model: folderTree, onSelectMedia: onSelectMedia)
                        } else {
                            switch viewModel.layout {
                            case .grid:
                                PosterGrid(spacing: 12, rowSpacing: 16) { cardWidth in
                                    browseItems(cardWidth: cardWidth)
                                }
                            case .list:
                                LazyVStack(spacing: 0) {
                                    browseItems()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .overlay {
                if viewModel.folderTree != nil {
                    EmptyView()
                } else if viewModel.isLoading, viewModel.browseItems.isEmpty {
                    ProgressView("library.browse.loading")
                } else if let errorMessage = viewModel.errorMessage, viewModel.browseItems.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater"),
                    )
                    .symbolRenderingMode(.multicolor)
                } else if viewModel.browseItems.isEmpty, viewModel.showsServerControls,
                          viewModel.controls.hasActiveFilters
                {
                    ContentUnavailableView {
                        Label("library.browse.empty.title", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("library.browse.empty.filtered.description")
                    } actions: {
                        Button("library.browse.empty.reset", action: viewModel.controls.resetSelection)
                    }
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
            .onChange(of: viewModel.scrollResetID) {
                proxy.scrollTo("libraryBrowseTop", anchor: .top)
            }
            .onChange(of: viewModel.isServerUnreachable) {
                Task { await viewModel.refresh() }
            }
        }
    }
}
