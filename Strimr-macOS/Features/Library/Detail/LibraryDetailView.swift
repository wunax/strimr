import SwiftUI

struct LibraryDetailView: View {
    @Environment(MediaServices.self) private var mediaServices
    @Environment(SettingsManager.self) private var settingsManager
    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var browseSession = LibraryBrowseSession()
    @State private var manageController = LibraryManageController()

    init(
        library: Library,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        self.library = library
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .recommended:
                    LibraryRecommendedView(
                        viewModel: LibraryRecommendedViewModel(
                            library: library,
                            services: mediaServices,
                            settingsManager: settingsManager,
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
        .toolbar {
            if availableTabs.count > 1 {
                ToolbarItem(placement: .principal) {
                    Picker(selection: selectedTabBinding) {
                        ForEach(availableTabs) { tab in
                            Text(tab.title).tag(tab)
                        }
                    } label: {
                        Text("library.detail.tabPicker")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            if !manageActions.actions(for: library).isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section(MediaQuickAction.manage.title) {
                            LibraryManageMenuItems(
                                library: library,
                                actions: manageActions,
                                controller: manageController,
                            )
                        }
                    } label: {
                        Label("common.actions.more", systemImage: "ellipsis")
                    }
                    .help(Text("common.actions.more"))
                }
            }
        }
        .libraryManagePresentation(manageController) { _ in manageActions }
    }

    private var manageActions: LibraryManageActions {
        LibraryManageActions(
            services: mediaServices,
            isReachable: !OfflineCoordinator.shared.isUnreachable(mediaServices.identity),
        )
    }

    private var availableTabs: [LibraryDetailTab] {
        LibraryDetailTab.available(
            for: library,
            provider: mediaServices.provider,
            displaysCollections: settingsManager.interface.displayCollections,
            displaysPlaylists: settingsManager.interface.displayPlaylists,
        )
    }

    private var preferencesKey: String {
        LibraryBrowsePreferences.key(scopeID: mediaServices.serverPreferencesScopeID, libraryID: library.id)
    }

    private var selectedTab: LibraryDetailTab {
        LibraryDetailTab.resolved(
            saved: settingsManager.libraryBrowsePreferences(for: preferencesKey).selectedTab,
            available: availableTabs,
            library: library,
        )
    }

    private var selectedTabBinding: Binding<LibraryDetailTab> {
        Binding { selectedTab } set: { select($0) }
    }

    private func select(_ tab: LibraryDetailTab) {
        var preferences = settingsManager.libraryBrowsePreferences(for: preferencesKey)
        preferences.setSelectedTab(tab, for: library)
        settingsManager.setLibraryBrowsePreferences(preferences, for: preferencesKey)
    }
}
