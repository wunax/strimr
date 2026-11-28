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
                    NavigationLink {
                        AccountsSettingsView()
                    } label: {
                        Label("settings.accounts.title", systemImage: "server.rack")
                    }
                    NavigationLink {
                        ProfilesSettingsView()
                    } label: {
                        Label("profiles.title", systemImage: "person.crop.circle")
                    }
                }
            }

            Section {
                NavigationLink {
                    SettingsPlaybackView()
                } label: {
                    Label("settings.playback.title", systemImage: "play.rectangle")
                }

                NavigationLink {
                    SettingsAudioView()
                } label: {
                    Label("settings.playback.audio.title", systemImage: "speaker.wave.2")
                }

                NavigationLink {
                    SettingsSubtitlesView()
                } label: {
                    Label("settings.playback.subtitles.title", systemImage: "captions.bubble")
                }

                NavigationLink {
                    AccountPreferencesView()
                } label: {
                    Label("settings.accountPreferences.title", systemImage: "person.text.rectangle")
                }

                NavigationLink {
                    SettingsInterfaceView(
                        settingsManager: settingsManager,
                        libraryStore: libraryStore,
                    )
                } label: {
                    Label("settings.interface.title", systemImage: "rectangle.grid.2x2")
                }

                #if os(macOS)
                    NavigationLink {
                        SettingsDownloadsView()
                    } label: {
                        Label("settings.downloads.title", systemImage: "arrow.down.circle")
                    }
                    NavigationLink {
                        SettingsStorageView()
                    } label: {
                        Label("settings.storage.title", systemImage: "internaldrive")
                    }
                    NavigationLink {
                        IntegrationsView()
                    } label: {
                        Label("settings.integrations.title", systemImage: "square.stack.3d.up")
                    }
                #endif
            }

            #if os(iOS)
                Section("settings.downloads.title") {
                    NavigationLink {
                        SettingsDownloadsView()
                    } label: {
                        Label("settings.downloads.manage", systemImage: "arrow.down.circle")
                    }

                    NavigationLink {
                        SettingsStorageView()
                    } label: {
                        Label("settings.storage.title", systemImage: "internaldrive")
                    }
                }

                Section("settings.integrations.title") {
                    NavigationLink {
                        IntegrationsView()
                    } label: {
                        Label("settings.integrations.manage", systemImage: "square.stack.3d.up")
                    }
                }
            #endif

            Section {
                NavigationLink {
                    SettingsPrivacyView()
                } label: {
                    Label("settings.privacy.title", systemImage: "hand.raised")
                }
            }

            Section {
                NavigationLink {
                    SettingsAboutView()
                } label: {
                    Label("settings.about.title", systemImage: "info.circle")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("settings.title")
    }
}
