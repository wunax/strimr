import SwiftUI

struct LibraryBrowseView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    @FocusState private var focusedCharacterId: String?

    private let listRowMetrics = MediaListRowMetrics(sizeClass: nil)

    init(
        viewModel: LibraryBrowseViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    private var folderTreeToggle: LibraryBrowseToggle? {
        guard viewModel.canShowFolderTree else { return nil }
        return .folderTree(isSelected: viewModel.showsFolderTree, action: viewModel.toggleFolderTree)
    }

    var body: some View {
        @Bindable var controls = viewModel.controls

        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 32) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        Color.clear
                            .frame(height: 0)
                            .id("libraryBrowseTop")

                        LibraryBrowseControlsView(
                            viewModel: controls,
                            showsBackButton: viewModel.canNavigateBack,
                            onNavigateBack: viewModel.navigateBack,
                            folderTreeToggle: folderTreeToggle,
                            layoutToggle: viewModel.folderTree == nil
                                ? .layout(current: viewModel.layout, onChange: viewModel.setLayout)
                                : nil,
                            itemCount: viewModel.folderTree == nil ? viewModel.totalItemCount : nil,
                        )

                        if let folderTree = viewModel.folderTree {
                            FolderTreeView(model: folderTree, onSelectMedia: onSelectMedia)
                        } else {
                            switch viewModel.layout {
                            case .grid:
                                PosterGrid(spacing: 32, rowSpacing: 32) { cardWidth in
                                    browseItems(cardWidth: cardWidth)
                                }
                            case .list:
                                LazyVStack(spacing: 0) {
                                    browseItems()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 32)
                    .padding(.bottom, 48)
                }
                // A fresh scroll view per folder level: tvOS otherwise keeps the old offset after the
                // focused card disappears, leaving a short folder scrolled out of view.
                .id(viewModel.folderPath)
                .frame(maxWidth: .infinity)

                if viewModel.showsCharacterColumn {
                    characterColumn(proxy: proxy)
                }
            }
            .overlay {
                if viewModel.folderTree != nil {
                    EmptyView()
                } else if viewModel.isLoading, viewModel.itemsByIndex.isEmpty {
                    ProgressView("library.browse.loading")
                } else if let errorMessage = viewModel.errorMessage, viewModel.itemsByIndex.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater"),
                    )
                    .symbolRenderingMode(.multicolor)
                } else if viewModel.totalItemCount == 0, !viewModel.isLoading, viewModel.controls.hasActiveFilters {
                    ContentUnavailableView {
                        Label("library.browse.empty.title", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("library.browse.empty.filtered.description")
                    } actions: {
                        Button("library.browse.empty.reset", action: viewModel.controls.resetSelection)
                    }
                } else if viewModel.totalItemCount == 0, !viewModel.isLoading {
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
        }
    }

    private func browseItems(cardWidth: CGFloat? = nil) -> some View {
        ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
            Group {
                if let item = viewModel.itemsByIndex[index] {
                    browseItem(item, cardWidth: cardWidth)
                } else {
                    ProgressView()
                        .frame(maxWidth: viewModel.layout == .list ? .infinity : nil)
                }
            }
            .frame(height: viewModel.layout == .list ? listRowMetrics.rowHeight : nil)
            .id(index)
            .onAppear {
                Task {
                    await viewModel.loadPagesAround(index: index)
                }
            }
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

    private func characterColumn(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 4) {
            ForEach(viewModel.sectionCharacters) { character in
                characterButton(character, proxy: proxy)
            }
        }
        .padding(.trailing, 20)
        .padding(.top, 20)
        .frame(width: 44, alignment: .top)
    }

    private func characterButton(
        _ character: LibraryBrowseViewModel.SectionCharacter,
        proxy: ScrollViewProxy,
    ) -> some View {
        let isFocused = focusedCharacterId == character.id
        return Button {
            Task {
                await viewModel.loadPagesAround(index: character.startIndex)
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(character.startIndex, anchor: .top)
                }
            }
        } label: {
            Text(character.title)
                .font(.caption2)
                .frame(width: 32, height: 32)
                .background(isFocused ? Color.white.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focusedCharacterId, equals: character.id)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
