import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @State private var showingExternalPlayerWarning = false

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    private var playerSelectionBinding: Binding<PlaybackPlayer> {
        Binding(
            get: { viewModel.playerBinding.wrappedValue },
            set: { newValue in
                viewModel.playerBinding.wrappedValue = newValue
                if newValue == .infuse {
                    showingExternalPlayerWarning = true
                }
            },
        )
    }

    var body: some View {
        List {
            Section("settings.playback.title") {
                Toggle("settings.playback.autoPlayNext", isOn: viewModel.autoPlayNextBinding)

                Picker("settings.playback.rewind", selection: viewModel.rewindBinding) {
                    ForEach(viewModel.seekOptions, id: \.self) { seconds in
                        Text("settings.playback.seconds \(seconds)").tag(seconds)
                    }
                }

                Picker("settings.playback.fastForward", selection: viewModel.fastForwardBinding) {
                    ForEach(viewModel.seekOptions, id: \.self) { seconds in
                        Text("settings.playback.seconds \(seconds)").tag(seconds)
                    }
                }

                Picker("settings.playback.player", selection: playerSelectionBinding) {
                    ForEach(viewModel.playerOptions) { player in
                        Text(LocalizedStringKey(player.localizationKey)).tag(player)
                    }
                }

                Picker("settings.playback.subtitleScale", selection: viewModel.subtitleScaleBinding) {
                    ForEach(viewModel.subtitleScaleOptions, id: \.self) { scale in
                        Text("settings.playback.scale \(scale)").tag(scale)
                    }
                }
            }

            Section("settings.download.title") {
                Toggle("settings.download.showAfterMovie", isOn: viewModel.showDownloadsAfterMovieBinding)
                Toggle("settings.download.showAfterEpisode", isOn: viewModel.showDownloadsAfterEpisodeBinding)
                Toggle("settings.download.showAfterShow", isOn: viewModel.showDownloadsAfterShowBinding)
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
        .navigationTitle("settings.title")
        .alert("settings.playback.player.externalWarning.title", isPresented: $showingExternalPlayerWarning) {
            Button("common.actions.done", role: .cancel) {}
        } message: {
            Text("settings.playback.player.externalWarning.message")
        }
    }
}
