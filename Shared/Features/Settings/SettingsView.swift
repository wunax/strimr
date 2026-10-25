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

                #if os(macOS)
                    NavigationLink("settings.downloads.title") {
                        SettingsDownloadsView()
                    }
                    NavigationLink("settings.storage.title") {
                        SettingsStorageView()
                    }
                    NavigationLink("settings.integrations.title") {
                        IntegrationsView()
                    }
                #endif
            }

            #if os(iOS)
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
            #endif

            Section {
                NavigationLink("settings.privacy.title") {
                    SettingsPrivacyView()
                }
            }

            Section {
                NavigationLink("settings.about.title") {
                    SettingsAboutView()
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("settings.title")
    }
}
