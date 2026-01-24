import SwiftUI

@MainActor
struct SettingsInterfaceView: View {
    let settingsManager: SettingsManager
    let libraryStore: LibraryStore

    var body: some View {
        List {
            Section {
                Toggle(
                    "settings.interface.displayCollections",
                    isOn: Binding(
                        get: { settingsManager.interface.displayCollections },
                        set: { settingsManager.setDisplayCollections($0) },
                    ),
                )
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
