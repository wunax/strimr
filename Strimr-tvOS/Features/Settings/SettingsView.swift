import SwiftUI

@MainActor
struct SettingsView: View {
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
            }

            Section("settings.integrations.title") {
                NavigationLink("settings.integrations.manage") {
                    IntegrationsView()
                }
            }
        }
        .navigationTitle("settings.title")
    }
}
