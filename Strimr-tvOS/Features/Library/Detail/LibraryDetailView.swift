import SwiftUI

struct LibraryDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var viewModel = LibraryDetailViewModel()
    @State private var selectedTab: LibraryDetailTab = .recommended
    @FocusState private var focusedSidebarItem: LibraryDetailTab?
    @FocusState private var contentFocused: Bool
    @Namespace private var focusNamespace

    init(
        library: Library,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        self.library = library
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            if selectedTab == .recommended, let heroMedia = viewModel.heroMedia {
                MediaHeroBackgroundView(media: heroMedia)
            }

            HStack(alignment: .center, spacing: 12) {
                sidebarContainer
                    .zIndex(1)
                contentView
                    .focusSection()
                    .overlay {
                        Color.black
                            .opacity(isSidebarFocused ? 0.35 : 0)
                            .ignoresSafeArea(edges: [.trailing, .top, .bottom])
                            .allowsHitTesting(false)
                    }
            }
            .focusScope(focusNamespace)
            .ignoresSafeArea(edges: [.leading])
            .animation(.easeInOut(duration: 0.2), value: isSidebarFocused)
        }
        .onAppear {
            contentFocused = true
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

    private var contentView: some View {
        Group {
            switch selectedTab {
            case .recommended:
                LibraryRecommendedView(
                    viewModel: LibraryRecommendedViewModel(
                        library: library,
                        context: plexApiContext,
                    ),
                    heroMedia: $viewModel.heroMedia,
                    onSelectMedia: onSelectMedia,
                )
            case .browse:
                LibraryBrowseView(
                    viewModel: LibraryBrowseViewModel(
                        library: library,
                        context: plexApiContext,
                        settingsManager: settingsManager,
                    ),
                    onSelectMedia: onSelectMedia,
                )
            case .collections:
                LibraryCollectionsView(
                    viewModel: LibraryCollectionsViewModel(
                        library: library,
                        context: plexApiContext,
                        settingsManager: settingsManager,
                    ),
                    onSelectMedia: onSelectMedia,
                )
            case .playlists:
                LibraryPlaylistsView(
                    viewModel: LibraryPlaylistsViewModel(
                        library: library,
                        context: plexApiContext,
                    ),
                    onSelectMedia: onSelectMedia,
                )
            }
        }
        .focused($contentFocused)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .prefersDefaultFocus(true, in: focusNamespace)
    }

    private var sidebarContainer: some View {
        Color.clear
            .frame(width: sidebarContainerWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) {
                sidebarView
                    .focusSection()
            }
    }

    private var sidebarView: some View {
        VStack(spacing: 36) {
            ForEach(availableTabs) { tab in
                sidebarButton(for: tab)
            }
        }
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity)
        .padding(.leading, 48)
        .padding(.trailing, 12)
        .background(alignment: .leading) {
            Rectangle()
                .fill(.regularMaterial)
                .frame(width: sidebarBackgroundWidth)
                .opacity(isSidebarFocused ? 1 : 0)
                .ignoresSafeArea(edges: [.leading, .top, .bottom])
        }
        .onMoveCommand { direction in
            guard direction == .right else { return }
            focusedSidebarItem = nil
            contentFocused = true
        }
    }

    private func sidebarButton(for tab: LibraryDetailTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.systemImageName)
                    .font(.caption)
                    .fontWeight(.semibold)
                if isSidebarFocused {
                    Text(tab.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selectedTab == tab ? .brandPrimary : .secondary)
        }
        .focused($focusedSidebarItem, equals: tab)
        .buttonStyle(.plain)
    }

    private var isSidebarFocused: Bool {
        focusedSidebarItem != nil
    }

    private var sidebarWidth: CGFloat {
        isSidebarFocused ? 240 : 72
    }

    private var sidebarContainerWidth: CGFloat {
        72 + 48 + 12
    }

    private var sidebarBackgroundWidth: CGFloat {
        240 + 48 + 12 + 48
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
