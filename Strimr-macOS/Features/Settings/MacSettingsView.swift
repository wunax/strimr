import SwiftUI

struct MacSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore

    var body: some View {
        List {
            Section {
                NavigationLink("settings.playback.title") {
                    SettingsPlaybackView()
                }
                NavigationLink("settings.interface.title") {
                    SettingsInterfaceView(
                        settingsManager: settingsManager,
                        libraryStore: libraryStore,
                    )
                }
                NavigationLink("settings.integrations.title") {
                    IntegrationsView()
                }
            }
        }
        .navigationTitle("settings.title")
    }
}
