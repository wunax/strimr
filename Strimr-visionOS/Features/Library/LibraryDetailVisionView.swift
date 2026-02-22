import SwiftUI

enum LibraryDetailTab: String, CaseIterable, Identifiable {
    case recommended
    case browse
    case collections
    case playlists

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .recommended:
            "library.detail.tab.recommended"
        case .browse:
            "library.detail.tab.browse"
        case .collections:
            "library.detail.tab.collections"
        case .playlists:
            "library.detail.tab.playlists"
        }
    }

    var systemImageName: String {
        switch self {
        case .recommended:
            "sparkles"
        case .browse:
            "square.grid.2x2.fill"
        case .collections:
            "rectangle.stack.fill"
        case .playlists:
            "music.note.list"
        }
    }
}

struct LibraryDetailVisionView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var selectedTab: LibraryDetailTab = .recommended

    init(
        library: Library,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        self.library = library
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(availableTabs) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImageName)
                    }
                    .listItemTint(selectedTab == tab ? .brandPrimary : .clear)
                }
            }
            .navigationTitle(library.title)
        } detail: {
            contentView
        }
        .onChange(of: settingsManager.interface.displayCollections) { _, displayCollections in
            if !displayCollections, selectedTab == .collections {
                selectedTab = .recommended
            }
        }
        .onChange(of: settingsManager.interface.displayPlaylists) { _, displayPlaylists in
            if !displayPlaylists, selectedTab == .playlists {
                selectedTab = .recommended
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .recommended:
            LibraryRecommendedVisionView(
                viewModel: LibraryRecommendedViewModel(
                    library: library,
                    context: plexApiContext,
                ),
                onSelectMedia: onSelectMedia,
            )
        case .browse:
            LibraryBrowseVisionView(
                viewModel: LibraryBrowseViewModel(
                    library: library,
                    context: plexApiContext,
                    settingsManager: settingsManager,
                ),
                onSelectMedia: onSelectMedia,
            )
        case .collections:
            LibraryCollectionsVisionView(
                viewModel: LibraryCollectionsViewModel(
                    library: library,
                    context: plexApiContext,
                    settingsManager: settingsManager,
                ),
                onSelectMedia: onSelectMedia,
            )
        case .playlists:
            LibraryPlaylistsVisionView(
                viewModel: LibraryPlaylistsViewModel(
                    library: library,
                    context: plexApiContext,
                ),
                onSelectMedia: onSelectMedia,
            )
        }
    }

    private var availableTabs: [LibraryDetailTab] {
        LibraryDetailTab.allCases.filter { tab in
            switch tab {
            case .collections:
                settingsManager.interface.displayCollections
            case .playlists:
                settingsManager.interface.displayPlaylists
            default:
                true
            }
        }
    }
}

struct LibraryRecommendedVisionView: View {
    @State var viewModel: LibraryRecommendedViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private let landscapeHubIdentifiers: [String] = ["inprogress"]

    init(
        viewModel: LibraryRecommendedViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ForEach(viewModel.hubs) { hub in
                    if hub.hasItems {
                        MediaHubSection(title: hub.title) {
                            carousel(for: hub)
                        }
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("library.recommended.loading")
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
            .padding(24)
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func carousel(for hub: Hub) -> some View {
        if shouldUseLandscape(for: hub) {
            MediaCarousel(
                layout: .landscape,
                items: hub.items,
                showsLabels: false,
                onSelectMedia: onSelectMedia,
            )
        } else {
            MediaCarousel(
                layout: .portrait,
                items: hub.items,
                showsLabels: false,
                onSelectMedia: onSelectMedia,
            )
        }
    }

    private func shouldUseLandscape(for hub: Hub) -> Bool {
        let identifier = hub.id.lowercased()
        return landscapeHubIdentifiers.contains { identifier.contains($0) }
    }
}

struct LibraryBrowseVisionView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 200), spacing: 20),
    ]

    init(
        viewModel: LibraryBrowseViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        @Bindable var controls = viewModel.controls

        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if controls.hasDisplayTypes {
                            LibraryBrowseControlsView(
                                viewModel: controls,
                                showsBackButton: viewModel.canNavigateBack,
                                onNavigateBack: viewModel.navigateBack,
                            )
                        }

                        LazyVGrid(columns: gridColumns, spacing: 20) {
                            ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
                                Group {
                                    if let item = viewModel.itemsByIndex[index] {
                                        switch item {
                                        case let .media(media):
                                            PortraitMediaCard(media: media, width: 180, showsLabels: true) {
                                                onSelectMedia(media)
                                            }
                                        case let .folder(folder):
                                            FolderCard(title: folder.title, width: 180, showsLabels: true) {
                                                viewModel.enterFolder(folder)
                                            }
                                        }
                                    } else {
                                        ProgressView()
                                    }
                                }
                                .id(index)
                                .onAppear {
                                    Task {
                                        await viewModel.loadPagesAround(index: index)
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity)

                if viewModel.showsCharacterColumn {
                    characterColumn(proxy: proxy)
                }
            }
            .overlay {
                if viewModel.isLoading, viewModel.itemsByIndex.isEmpty {
                    ProgressView("library.browse.loading")
                } else if let errorMessage = viewModel.errorMessage, viewModel.itemsByIndex.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater"),
                    )
                    .symbolRenderingMode(.multicolor)
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
        }
    }

    private func characterColumn(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 4) {
            ForEach(viewModel.sectionCharacters) { character in
                Button {
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
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
        }
        .padding(.trailing, 16)
        .padding(.top, 16)
        .frame(width: 48, alignment: .top)
    }
}

struct LibraryCollectionsVisionView: View {
    @State var viewModel: LibraryCollectionsViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 200), spacing: 20),
    ]

    init(
        viewModel: LibraryCollectionsViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
                            Group {
                                if let media = viewModel.itemsByIndex[index] {
                                    PortraitMediaCard(media: media, width: 180, showsLabels: true) {
                                        onSelectMedia(media)
                                    }
                                } else {
                                    ProgressView()
                                }
                            }
                            .id(index)
                            .onAppear {
                                Task {
                                    await viewModel.loadPagesAround(index: index)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity)

                characterColumn(proxy: proxy)
            }
            .overlay {
                if viewModel.isLoading, viewModel.itemsByIndex.isEmpty {
                    ProgressView("library.browse.loading")
                } else if let errorMessage = viewModel.errorMessage, viewModel.itemsByIndex.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater"),
                    )
                    .symbolRenderingMode(.multicolor)
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
        }
    }

    private func characterColumn(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 4) {
            ForEach(viewModel.sectionCharacters) { character in
                Button {
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
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
        }
        .padding(.trailing, 16)
        .padding(.top, 16)
        .frame(width: 48, alignment: .top)
    }
}

struct LibraryPlaylistsVisionView: View {
    @State var viewModel: LibraryPlaylistsViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 200), spacing: 20),
    ]

    init(
        viewModel: LibraryPlaylistsViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(viewModel.items) { media in
                    PortraitMediaCard(media: media, width: 180, showsLabels: true) {
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
            .padding(24)
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
    }
}
