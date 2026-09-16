import SwiftUI

struct LibraryDetailView: View {
    @Environment(MediaServices.self) private var mediaServices
    @Environment(SettingsManager.self) private var settingsManager
    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var selectedTab: LibraryDetailTab = .recommended
    @State private var browseSession = LibraryBrowseSession()

    init(
        library: Library,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        self.library = library
        self.onSelectMedia = onSelectMedia
        _selectedTab = State(
            initialValue: library.type == .collection || library.type == .playlist ? .browse : .recommended,
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if availableTabs.count > 1 {
                LibraryDetailTabPicker(selection: $selectedTab, tabs: availableTabs)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            Group {
                switch selectedTab {
                case .recommended:
                    LibraryRecommendedView(
                        viewModel: LibraryRecommendedViewModel(
                            library: library,
                            services: mediaServices,
                        ),
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(library.title)
        .toolbarTitleDisplayMode(.inline)
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

    private var availableTabs: [LibraryDetailTab] {
        if mediaServices.provider == .jellyfin {
            return library.type == .collection || library.type == .playlist
                ? [.browse]
                : [.recommended, .browse]
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
