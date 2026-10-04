import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        List {
            if sessionManager.canManageAccounts {
                Section {
                    NavigationLink("settings.accounts.title") {
                        AccountsSettingsView()
                    }
                    NavigationLink("profiles.title") {
                        ProfilesSettingsView()
                    }
                }
            }

            Section {
                NavigationLink("settings.playback.title") {
                    SettingsPlaybackView()
                }

                NavigationLink("settings.playback.audio.title") {
                    SettingsAudioView()
                }

                NavigationLink("settings.playback.subtitles.title") {
                    SettingsSubtitlesView()
                }

                NavigationLink("settings.interface.title") {
                    SettingsInterfaceView(
                        settingsManager: settingsManager,
                        libraryStore: libraryStore,
                    )
                }
            }

            Section("settings.downloads.title") {
                NavigationLink("settings.downloads.manage") {
                    SettingsDownloadsView()
                }

                NavigationLink("settings.storage.title") {
                    SettingsStorageView()
                }
            }

            Section("settings.integrations.title") {
                NavigationLink("settings.integrations.manage") {
                    IntegrationsView()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("settings.title")
    }
}
