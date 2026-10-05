import SwiftUI

@MainActor
struct SettingsInterfaceView: View {
    @Environment(SessionManager.self) private var sessionManager
    let settingsManager: SettingsManager
    let libraryStore: LibraryStore

    var body: some View {
        SettingsList {
            Section("settings.interface.homeRows.section") {
                SettingsLink("settings.interface.homeRows.title") {
                    HomeRowsSettingsView(
                        sessionManager: sessionManager,
                        settingsManager: settingsManager,
                    )
                }
                .settingsFocus("homeRows", isDefault: true)
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

            Section {
                SettingsPicker(
                    "settings.interface.posterSize",
                    selection: Binding(
                        get: { settingsManager.interface.posterSize },
                        set: { settingsManager.setPosterSize($0) },
                    ),
                    options: Array(PosterSize.allCases),
                ) { option in
                    Text(option.title)
                }
                .settingsFocus("posterSize")
            } footer: {
                Text("settings.interface.posterSize.footer")
            }

            Section {
                SettingsPicker(
                    "settings.interface.libraries.defaultLayout",
                    selection: Binding(
                        get: { settingsManager.interface.libraryDefaultLayout },
                        set: { settingsManager.setLibraryDefaultLayout($0) },
                    ),
                    options: Array(LibraryDefaultLayout.allCases),
                ) { option in
                    Text(option.title)
                }
                .settingsFocus("libraryDefaultLayout")
                Button("settings.interface.libraries.resetLayouts \(settingsManager.customLibraryLayoutCount)") {
                    settingsManager.resetLibraryLayouts()
                }
                .disabled(settingsManager.customLibraryLayoutCount == 0)
                .settingsFocus("resetLibraryLayouts")
            } header: {
                Text("settings.interface.libraries.section")
            } footer: {
                Text("settings.interface.libraries.footer")
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
