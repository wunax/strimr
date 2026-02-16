import SwiftUI

struct SettingsVisionView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SettingsPlaybackVisionView()
                } label: {
                    Label("settings.playback.title", systemImage: "play.rectangle.fill")
                }

                NavigationLink {
                    SettingsInterfaceVisionView()
                } label: {
                    Label("settings.interface.title", systemImage: "rectangle.grid.2x2.fill")
                }
            }

            Section {
                NavigationLink {
                    IntegrationsVisionView()
                } label: {
                    Label("settings.integrations.title", systemImage: "puzzlepiece.extension.fill")
                }
            }
        }
        .navigationTitle("settings.title")
    }
}

struct SettingsPlaybackVisionView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        List {
            Section("settings.playback.general") {
                Toggle(
                    "settings.playback.autoPlayNextEpisode",
                    isOn: Binding(
                        get: { settingsManager.playback.autoPlayNextEpisode },
                        set: { settingsManager.setAutoPlayNextEpisode($0) }
                    )
                )
            }

            Section("settings.playback.seeking") {
                Picker(
                    "settings.playback.seekBackward",
                    selection: Binding(
                        get: { settingsManager.playback.seekBackwardSeconds },
                        set: { settingsManager.setSeekBackwardSeconds($0) }
                    )
                ) {
                    ForEach([5, 10, 15, 30, 45, 60], id: \.self) { value in
                        Text("\(value)s").tag(value)
                    }
                }

                Picker(
                    "settings.playback.seekForward",
                    selection: Binding(
                        get: { settingsManager.playback.seekForwardSeconds },
                        set: { settingsManager.setSeekForwardSeconds($0) }
                    )
                ) {
                    ForEach([5, 10, 15, 30, 45, 60], id: \.self) { value in
                        Text("\(value)s").tag(value)
                    }
                }
            }

            Section("settings.playback.subtitles") {
                Picker(
                    "settings.playback.subtitleScale",
                    selection: Binding(
                        get: { settingsManager.playback.subtitleScale },
                        set: { settingsManager.setSubtitleScale($0) }
                    )
                ) {
                    ForEach([50, 75, 100, 125, 150], id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
            }
        }
        .navigationTitle("settings.playback.title")
    }
}

struct SettingsInterfaceVisionView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore

    var body: some View {
        List {
            Section("settings.interface.display") {
                Toggle(
                    "settings.interface.displayCollections",
                    isOn: Binding(
                        get: { settingsManager.interface.displayCollections },
                        set: { settingsManager.setDisplayCollections($0) }
                    )
                )
                Toggle(
                    "settings.interface.displayPlaylists",
                    isOn: Binding(
                        get: { settingsManager.interface.displayPlaylists },
                        set: { settingsManager.setDisplayPlaylists($0) }
                    )
                )
                Toggle(
                    "settings.interface.displaySeerrTab",
                    isOn: Binding(
                        get: { settingsManager.interface.displaySeerrDiscoverTab },
                        set: { settingsManager.setDisplaySeerrDiscoverTab($0) }
                    )
                )
            }

            Section("settings.interface.hiddenLibraries") {
                NavigationLink {
                    DisplayedLibrariesSectionView(
                        settingsManager: settingsManager,
                        libraryStore: libraryStore,
                    )
                } label: {
                    Text("settings.interface.manageHiddenLibraries")
                }
            }

            Section("settings.interface.navigationLibraries") {
                NavigationLink {
                    NavigationLibrariesSectionView(
                        settingsManager: settingsManager,
                        libraryStore: libraryStore,
                    )
                } label: {
                    Text("settings.interface.manageNavigationLibraries")
                }
            }
        }
        .navigationTitle("settings.interface.title")
    }
}

struct IntegrationsVisionView: View {
    @Environment(SeerrStore.self) private var seerrStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SeerrIntegrationVisionView()
                } label: {
                    HStack {
                        Label("settings.integrations.seerr", systemImage: "ticket.fill")
                        Spacer()
                        if seerrStore.isLoggedIn {
                            Text("settings.integrations.connected")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("settings.integrations.title")
    }
}

struct SeerrIntegrationVisionView: View {
    @Environment(SeerrStore.self) private var seerrStore
    @State private var viewModel: SeerrViewModel?

    var body: some View {
        Group {
            if seerrStore.isLoggedIn {
                connectedView
            } else {
                setupView
            }
        }
        .navigationTitle("settings.integrations.seerr")
    }

    private var connectedView: some View {
        List {
            Section {
                if let user = seerrStore.user {
                    LabeledContent("settings.seerr.user", value: user.displayName ?? "")
                }
                if let baseURL = seerrStore.baseURLString {
                    LabeledContent("settings.seerr.server", value: baseURL)
                }
            }

            Section {
                Button("settings.seerr.disconnect", role: .destructive) {
                    seerrStore.clearUser()
                }
            }
        }
    }

    @ViewBuilder
    private var setupView: some View {
        VStack(spacing: 24) {
            Text("settings.seerr.setup.description")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("settings.seerr.setup.instructions")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
