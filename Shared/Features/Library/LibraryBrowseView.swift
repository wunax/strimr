import SwiftUI

struct LibraryBrowseView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(MediaServices.self) private var mediaServices: MediaServices?
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    #if os(iOS)
        @State private var scrollMetrics = LibraryScrollMetrics()
        @State private var isScrolling = false
        @State private var isPointerNearEdge = false
    #elseif os(macOS)
        @State private var firstVisibleIndex: Int?
        @FocusState private var isGridFocused: Bool
    #endif

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

    private let pageMargin: CGFloat = 16

    private var isEmpty: Bool {
        viewModel.totalItemCount == 0
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
                        itemCount: viewModel.folderTree == nil ? viewModel.itemCount : nil,
                    )
                    .padding(.horizontal, pageMargin)

                    Group {
                        if let folderTree = viewModel.folderTree {
                            FolderTreeView(model: folderTree, onSelectMedia: onSelectMedia)
                        } else {
                            switch viewModel.layout {
                            case .grid:
                                PosterGrid(spacing: 12, rowSpacing: 16) { cardWidth in
                                    if viewModel.isLoading, isEmpty {
                                        PosterSkeletonCards(
                                            width: cardWidth,
                                            showsLabels: settingsManager.interface.showsCardLabels,
                                        )
                                    }
                                    browseItems(cardWidth: cardWidth)
                                }
                            case .list:
                                LazyVStack(spacing: 0) {
                                    browseItems()
                                }
                                .scrollTargetLayout()
                            }
                        }
                    }
                    .padding(.horizontal, pageMargin)
                    .padding(.trailing, sectionIndexInset)
                }
            }
            #if os(iOS)
            .scrollIndicators(showsScrubber ? .hidden : .automatic)
            .onScrollGeometryChange(for: LibraryScrollMetrics.self) { geometry in
                LibraryScrollMetrics(geometry)
            } action: { _, metrics in
                scrollMetrics = metrics
            }
            .onScrollPhaseChange { _, phase in
                isScrolling = phase.isScrolling
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    isPointerNearEdge = location.x > scrollMetrics.containerSize.width - 44
                case .ended:
                    isPointerNearEdge = false
                }
            }
            .overlay(alignment: .trailing) {
                if showsScrubber {
                    scrubber(proxy: proxy)
                }
            }
            #elseif os(macOS)
            .onScrollTargetVisibilityChange(idType: Int.self) { indexes in
                firstVisibleIndex = indexes.min()
            }
            .overlay(alignment: .trailing) {
                if let sectionIndex = viewModel.visibleSectionIndex {
                    LibrarySectionIndexView(
                        sectionIndex: sectionIndex,
                        currentSection: firstVisibleIndex.flatMap(sectionIndex.section(containing:)),
                    ) { section in
                        jump(to: section, proxy: proxy)
                    }
                    .padding(.trailing, Self.scrollBarClearance)
                }
            }
            .focusable()
            .focused($isGridFocused)
            .focusEffectDisabled()
            .onKeyPress(characters: .alphanumerics, phases: .down) { press in
                jumpToTypedCharacter(press, proxy: proxy)
            }
            .onAppear { isGridFocused = true }
            #endif
            .overlay {
                stateOverlay
            }
            .task {
                await viewModel.load()
            }
            .onChange(of: mediaServices?.deletedMediaIDs) {
                viewModel.removeDeletedItems(ids: mediaServices?.deletedMediaIDs ?? [])
            }
            .onChange(of: viewModel.scrollResetID) {
                proxy.scrollTo("libraryBrowseTop", anchor: .top)
            }
            .onChange(of: viewModel.isServerUnreachable) {
                Task { await viewModel.refresh() }
            }
        }
    }

    private func browseItems(cardWidth: CGFloat? = nil) -> some View {
        ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
            Group {
                if let item = viewModel.itemsByIndex[index] {
                    browseItem(item, cardWidth: cardWidth)
                } else if viewModel.layout == .grid {
                    PosterSkeletonCard(width: cardWidth, showsLabels: settingsManager.interface.showsCardLabels)
                } else {
                    ListRowSkeleton()
                }
            }
            .id(index)
            .onAppear {
                viewModel.itemAppeared(at: index)
            }
        }
    }

    @ViewBuilder
    private func browseItem(_ item: LibraryBrowseItem, cardWidth: CGFloat?) -> some View {
        switch (item, viewModel.layout) {
        case let (.media(media), .grid):
            PortraitMediaCard(media: media, width: cardWidth, showsLabels: settingsManager.interface.showsCardLabels) {
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

    @ViewBuilder
    private var stateOverlay: some View {
        if viewModel.folderTree != nil {
            EmptyView()
        } else if viewModel.isLoading, isEmpty {
            if viewModel.layout == .list {
                ProgressView("library.browse.loading")
            }
        } else if let errorMessage = viewModel.errorMessage, isEmpty {
            ContentUnavailableView(
                errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                description: Text("common.errors.tryAgainLater"),
            )
            .symbolRenderingMode(.multicolor)
        } else if isEmpty, viewModel.showsServerControls, viewModel.controls.hasActiveFilters {
            ContentUnavailableView {
                Label("library.browse.empty.title", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("library.browse.empty.filtered.description")
            } actions: {
                Button("library.browse.empty.reset", action: viewModel.controls.resetSelection)
            }
        } else if isEmpty {
            ContentUnavailableView(
                "library.browse.empty.title",
                systemImage: "square.grid.2x2.fill",
                description: Text("library.browse.empty.description"),
            )
        }
    }

    #if os(iOS)
        private var sectionIndexInset: CGFloat {
            0
        }

        private var showsScrubber: Bool {
            viewModel.canScrub && scrollMetrics.isLongEnoughToScrub
        }

        private func scrubber(proxy: ScrollViewProxy) -> some View {
            LibraryScrubber(
                totalCount: viewModel.totalItemCount,
                sectionIndex: viewModel.visibleSectionIndex,
                scrollFraction: scrollMetrics.fraction,
                isScrolling: isScrolling,
                isPointerNearby: isPointerNearEdge,
                onBegin: viewModel.beginScrubbing,
                onScrub: { index in
                    viewModel.scrub(to: index)
                    proxy.scrollTo(index, anchor: .top)
                },
                onEnd: viewModel.endScrubbing,
            )
        }
    #elseif os(macOS)
        /// Keeps the letters clear of the overlay scroll bar.
        private static let scrollBarClearance: CGFloat = 14

        private var sectionIndexInset: CGFloat {
            guard viewModel.visibleSectionIndex != nil else { return 0 }
            return LibrarySectionIndexView.width + Self.scrollBarClearance + 4 - pageMargin
        }

        private func jump(to section: LibrarySectionIndex.Section, proxy: ScrollViewProxy) {
            viewModel.jump(to: section)
            proxy.scrollTo(section.startIndex, anchor: .top)
        }

        private func jumpToTypedCharacter(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
            guard press.modifiers.isDisjoint(with: [.command, .option, .control]),
                  let sectionIndex = viewModel.visibleSectionIndex,
                  let character = press.characters.first,
                  let section = sectionIndex.section(forTypedCharacter: character) else { return .ignored }
            jump(to: section, proxy: proxy)
            return .handled
        }
    #endif
}
