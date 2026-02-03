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

            HStack(alignment: .center, spacing: 36) {
                sidebarView
                    .focusSection()
                contentView
                    .focusSection()
            }
            .focusScope(focusNamespace)
            .ignoresSafeArea(edges: [.leading])
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
                LibraryTVRecommendedView(
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

    private var sidebarView: some View {
        VStack {
            ForEach(availableTabs) { tab in
                sidebarButton(for: tab)
            }
        }
        .frame(maxWidth: sidebarWidth, maxHeight: .infinity)
        .padding(.leading, 36)
        .animation(.easeInOut(duration: 0.2), value: isSidebarFocused)
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
