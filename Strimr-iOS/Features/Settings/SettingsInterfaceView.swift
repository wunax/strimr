import SwiftUI

@MainActor
struct SettingsInterfaceView: View {
    @Environment(SessionManager.self) private var sessionManager
    let settingsManager: SettingsManager
    let libraryStore: LibraryStore

    var body: some View {
        List {
            Section("settings.interface.homeRows.section") {
                NavigationLink("settings.interface.homeRows.title") {
                    HomeRowsSettingsView(
                        sessionManager: sessionManager,
                        settingsManager: settingsManager,
                    )
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

            Section {
                Picker(
                    "settings.interface.posterSize",
                    selection: Binding(
                        get: { settingsManager.interface.posterSize },
                        set: { settingsManager.setPosterSize($0) },
                    ),
                ) {
                    ForEach(PosterSize.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
            } footer: {
                Text("settings.interface.posterSize.footer")
            }

            Section {
                Picker(
                    "settings.interface.libraries.defaultLayout",
                    selection: Binding(
                        get: { settingsManager.interface.libraryDefaultLayout },
                        set: { settingsManager.setLibraryDefaultLayout($0) },
                    ),
                ) {
                    ForEach(LibraryDefaultLayout.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                Button("settings.interface.libraries.resetLayouts \(settingsManager.customLibraryLayoutCount)") {
                    settingsManager.resetLibraryLayouts()
                }
                .disabled(settingsManager.customLibraryLayoutCount == 0)
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
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .navigationTitle("settings.interface.title")
    }
}
