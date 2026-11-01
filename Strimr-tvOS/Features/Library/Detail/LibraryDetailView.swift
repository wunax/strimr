import SwiftUI

struct LibraryDetailView: View {
    @Environment(MediaServices.self) private var mediaServices
    @Environment(SettingsManager.self) private var settingsManager
    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var viewModel = LibraryDetailViewModel()
    @State private var selectedTab: LibraryDetailTab = .recommended
    @State private var browseSession = LibraryBrowseSession()
    @State private var manageController = LibraryManageController()
    @FocusState private var focusedSidebarItem: LibraryDetailTab?
    @FocusState private var isManageButtonFocused: Bool
    @FocusState private var contentFocused: Bool
    @Namespace private var focusNamespace

    init(
        library: Library,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        self.library = library
        self.onSelectMedia = onSelectMedia
        _selectedTab = State(
            initialValue: library.isShared || library.type == .collection || library.type == .playlist
                ? .browse : .recommended,
        )
    }

    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            if selectedTab == .recommended, let heroMedia = viewModel.heroMedia {
                MediaHeroBackgroundView(media: heroMedia)
            }

            if settingsManager.interface.tabBarPlacement == .sidebar {
                chipsLayout
            } else {
                sidebarLayout
            }
        }
        .onAppear {
            contentFocused = true
        }
        .libraryManagePresentation(manageController) { _ in manageActions }
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

    /// The app sidebar already sits on the leading edge, so the library sections move to chips on top.
    private var chipsLayout: some View {
        VStack(alignment: .leading, spacing: 24) {
            if availableTabs.count > 1 {
                LibraryDetailTabPicker(selection: $selectedTab, tabs: availableTabs) {
                    if canManage {
                        Button {
                            openManageDialog()
                        } label: {
                            // Inside a text so the chip takes the line height of the tab chips.
                            Text(Image(systemName: "ellipsis"))
                        }
                        .buttonStyle(.chip(isSelected: false))
                        .disabled(manageController.isPerforming)
                        .accessibilityLabel(Text(MediaQuickAction.manage.title))
                    }
                }
                .focusSection()
            }
            contentView
                .focusSection()
        }
        .focusScope(focusNamespace)
    }

    private var sidebarLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            if availableTabs.count > 1 {
                sidebarContainer
                    .zIndex(1)
            }
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
        // The sidebar supplies the leading margin; without it, the safe area does.
        .ignoresSafeArea(edges: availableTabs.count > 1 ? [.leading] : [])
        .animation(.easeInOut(duration: 0.2), value: isSidebarFocused)
    }

    private var contentView: some View {
        Group {
            switch selectedTab {
            case .recommended:
                LibraryRecommendedView(
                    viewModel: LibraryRecommendedViewModel(
                        library: library,
                        services: mediaServices,
                    ),
                    heroMedia: $viewModel.heroMedia,
                    onSelectMedia: onSelectMedia,
                )
            case .browse:
                LibraryBrowseView(
                    viewModel: LibraryBrowseViewModel(
                        library: library,
                        services: mediaServices,
                        settingsManager: settingsManager,
                        browseSession: browseSession,
                    ),
                    onSelectMedia: onSelectMedia,
                )
            case .collections:
                LibraryCollectionsView(
                    viewModel: LibraryCollectionsViewModel(
                        library: library,
                        services: mediaServices,
                        settingsManager: settingsManager,
                    ),
                    onSelectMedia: onSelectMedia,
                )
            case .playlists:
                LibraryPlaylistsView(
                    viewModel: LibraryPlaylistsViewModel(
                        library: library,
                        services: mediaServices,
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
        .overlay(alignment: .bottom) {
            if canManage {
                sidebarManageButton
                    .padding(.bottom, 48)
            }
        }
        .padding(.leading, 48)
        .padding(.trailing, 12)
        .background(alignment: .leading) {
            Color.clear
                .glassSurface(in: Rectangle())
                .frame(width: sidebarBackgroundWidth)
                .opacity(isSidebarFocused ? 1 : 0)
                .ignoresSafeArea(edges: [.leading, .top, .bottom])
        }
        .onMoveCommand { direction in
            guard direction == .right else { return }
            focusedSidebarItem = nil
            isManageButtonFocused = false
            contentFocused = true
        }
    }

    private func sidebarButton(for tab: LibraryDetailTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            sidebarLabel(title: tab.title, systemImage: tab.systemImageName)
                // Hierarchical so the system focus, which turns the button white, inverts it.
                .foregroundStyle(selectedTab == tab ? HierarchicalShapeStyle.primary : .secondary)
        }
        .focused($focusedSidebarItem, equals: tab)
        .buttonStyle(.plain)
    }

    private func sidebarLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.caption)
                .fontWeight(.semibold)
            if isSidebarFocused {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sidebarManageButton: some View {
        Button {
            openManageDialog()
        } label: {
            sidebarLabel(title: MediaQuickAction.manage.title, systemImage: "ellipsis")
                .foregroundStyle(.secondary)
        }
        .focused($isManageButtonFocused)
        .buttonStyle(.plain)
        .disabled(manageController.isPerforming)
    }

    private func openManageDialog() {
        manageController.dialogLibrary = library
    }

    private var manageActions: LibraryManageActions {
        LibraryManageActions(services: mediaServices, isReachable: true)
    }

    private var canManage: Bool {
        !manageActions.actions(for: library).isEmpty
    }

    private var isSidebarFocused: Bool {
        focusedSidebarItem != nil || isManageButtonFocused
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
        if mediaServices.provider == .jellyfin {
            return library.type == .collection || library.type == .playlist
                ? [.browse]
                : [.recommended, .browse]
        }
        if library.isShared {
            return [.browse]
        }
        return LibraryDetailTab.allCases.filter { tab in
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
