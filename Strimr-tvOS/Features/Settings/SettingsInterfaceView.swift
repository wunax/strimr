import SwiftUI

@MainActor
struct SettingsInterfaceView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(MediaServices.self) private var mediaServices
    let settingsManager: SettingsManager
    let libraryStore: LibraryStore

    var body: some View {
        SettingsList {
            Section("settings.interface.homeRows.section") {
                SettingsLink("settings.interface.homeRows.title") {
                    HomeRowsSettingsView(
                        services: mediaServices,
                        settingsManager: settingsManager,
                        libraryStore: libraryStore,
                    )
                }
                .settingsFocus("homeRows", isDefault: true)
            }

            if sessionManager.provider == .plex {
                Section {
                    Toggle(
                        "settings.interface.multiServerSearch",
                        isOn: Binding(
                            get: { settingsManager.interface.multiServerSearchEnabled },
                            set: { settingsManager.setMultiServerSearchEnabled($0) },
                        ),
                    )
                    .settingsFocus("settings.interface.multiServerSearch")
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
                .settingsFocus("settings.interface.displayCollections")
                Toggle(
                    "settings.interface.displayPlaylists",
                    isOn: Binding(
                        get: { settingsManager.interface.displayPlaylists },
                        set: { settingsManager.setDisplayPlaylists($0) },
                    ),
                )
                .settingsFocus("settings.interface.displayPlaylists")
                Toggle(
                    "settings.interface.displayFavoritesTab",
                    isOn: Binding(
                        get: { settingsManager.interface.displayFavoritesTab },
                        set: { settingsManager.setDisplayFavoritesTab($0) },
                    ),
                )
                .settingsFocus("settings.interface.displayFavoritesTab")
            } footer: {
                Text("settings.interface.displayFavoritesTab.description")
            }

            Section {
                Toggle(
                    "settings.interface.displayLiveTVTab",
                    isOn: Binding(
                        get: { settingsManager.interface.displayLiveTVTab },
                        set: { settingsManager.setDisplayLiveTVTab($0) },
                    ),
                )
                .settingsFocus("settings.interface.displayLiveTVTab")
            } footer: {
                Text("settings.interface.displayLiveTVTab.description")
            }

            Section {
                SettingsPicker(
                    "settings.interface.spoilerProtection.title",
                    selection: Binding(
                        get: { settingsManager.interface.spoilerProtection },
                        set: { settingsManager.setSpoilerProtection($0) },
                    ),
                    options: Array(SpoilerProtectionLevel.allCases),
                ) { level in
                    Text(level.title)
                }
                .settingsFocus("spoilerProtection")
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
    }
}
