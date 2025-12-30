import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
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

                Picker("settings.playback.player", selection: viewModel.playerBinding) {
                    ForEach(viewModel.playerOptions) { player in
                        Text(player.localizationKey).tag(player)
                    }
                }

                Picker("settings.playback.subtitleScale", selection: viewModel.subtitleScaleBinding) {
                    ForEach(viewModel.subtitleScaleOptions, id: \.self) { scale in
                        Text("settings.playback.scale \(scale)").tag(scale)
                    }
                }
            }

            DisplayedLibrariesSectionView(
                settingsManager: settingsManager,
                plexApiContext: plexApiContext
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle("settings.title")
    }
}
