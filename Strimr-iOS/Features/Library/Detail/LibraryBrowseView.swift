import SwiftUI

struct LibraryBrowseView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private var cardWidth: CGFloat {
        settingsManager.interface.posterSize.gridCardWidth
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12, alignment: .top),
        ]
    }

    private var downloadedOnlyToggle: LibraryBrowseToggle? {
        guard viewModel.showsDownloadedOnlyToggle else { return nil }
        return LibraryBrowseToggle(
            title: String(localized: "offline.library.downloadedOnly"),
            systemImage: "arrow.down.circle",
            isSelected: viewModel.isDownloadedOnly,
            action: viewModel.toggleDownloadedOnly,
        )
    }

    @ViewBuilder
    private var browseItems: some View {
        ForEach(Array(viewModel.browseItems.enumerated()), id: \.element.id) { index, item in
            browseItem(item)
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
    private func browseItem(_ item: LibraryBrowseItem) -> some View {
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
                        layoutToggle: .layout(current: viewModel.layout, onChange: viewModel.setLayout),
                        itemCount: viewModel.totalCount,
                    )
                    .padding(.horizontal, 16)

                    Group {
                        switch viewModel.layout {
                        case .grid:
                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                browseItems
                            }
                        case .list:
                            LazyVStack(spacing: 0) {
                                browseItems
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
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
