import SwiftUI

@MainActor
struct LibrariesSettingsView: View {
    let settingsManager: SettingsManager
    let libraryStore: LibraryStore

    var body: some View {
        #if os(tvOS)
            SettingsList { sections }
        #else
            List { sections }
                .insetListStyle()
                .navigationTitle("settings.interface.manageLibraries")
        #endif
    }

    @ViewBuilder
    private var sections: some View {
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
