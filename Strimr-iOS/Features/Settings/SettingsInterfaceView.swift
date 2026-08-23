import SwiftUI

@MainActor
struct SettingsInterfaceView: View {
    @Environment(SessionManager.self) private var sessionManager
    let settingsManager: SettingsManager
    let libraryStore: LibraryStore

    var body: some View {
        List {
            if sessionManager.provider == .plex {
                Section {
                    Toggle(
                        "settings.interface.multiServerSearch",
                        isOn: Binding(
                            get: { settingsManager.interface.multiServerSearchEnabled },
                            set: { settingsManager.setMultiServerSearchEnabled($0) },
                        ),
                    )
                } footer: {
                    Text("settings.interface.multiServerSearch.description")
                }
            }

            Section {
                Toggle(
                    "settings.interface.displayCollections",
                    isOn: Binding(
                        get: { settingsManager.interface.displayCollections },
                        set: { settingsManager.setDisplayCollections($0) },
                    ),
                )
                Toggle(
                    "settings.interface.displayPlaylists",
                    isOn: Binding(
                        get: { settingsManager.interface.displayPlaylists },
                        set: { settingsManager.setDisplayPlaylists($0) },
                    ),
                )
            }

            Section {
                Toggle(
                    "settings.interface.displayFavoritesTab",
                    isOn: Binding(
                        get: { settingsManager.interface.displayFavoritesTab },
                        set: { settingsManager.setDisplayFavoritesTab($0) },
                    ),
                )
            } footer: {
                Text("settings.interface.displayFavoritesTab.description")
            }

            Section {
                Toggle(
                    "settings.interface.displayDownloadsTab",
                    isOn: Binding(
                        get: { settingsManager.interface.displayDownloadsTab },
                        set: { settingsManager.setDisplayDownloadsTab($0) },
                    ),
                )
            } footer: {
                Text("settings.interface.displayDownloadsTab.description")
            }

            Section {
                Toggle(
                    "settings.interface.displayLiveTVTab",
                    isOn: Binding(
                        get: { settingsManager.interface.displayLiveTVTab },
                        set: { settingsManager.setDisplayLiveTVTab($0) },
                    ),
                )
            } footer: {
                Text("settings.interface.displayLiveTVTab.description")
            }

            Section {
                Picker(
                    "settings.interface.spoilerProtection.title",
                    selection: Binding(
                        get: { settingsManager.interface.spoilerProtection },
                        set: { settingsManager.setSpoilerProtection($0) },
                    ),
                ) {
                    ForEach(SpoilerProtectionLevel.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
            } footer: {
                Text("settings.interface.spoilerProtection.description")
            }

            DisplayedLibrariesSectionView(
                settingsManager: settingsManager,
                libraryStore: libraryStore,
            )

            NavigationLibrariesSectionView(
                settingsManager: settingsManager,
                libraryStore: libraryStore,
            )
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("settings.interface.title")
    }
}
