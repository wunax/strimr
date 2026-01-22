import SwiftUI

@MainActor
struct SettingsPlaybackView: View {
    @Environment(SettingsManager.self) private var settingsManager
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
                .pickerStyle(.navigationLink)

                Picker("settings.playback.fastForward", selection: viewModel.fastForwardBinding) {
                    ForEach(viewModel.seekOptions, id: \.self) { seconds in
                        Text("settings.playback.seconds \(seconds)").tag(seconds)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("settings.playback.player", selection: playerSelectionBinding) {
                    ForEach(viewModel.playerOptions) { player in
                        Text(LocalizedStringKey(player.localizationKey)).tag(player)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("settings.playback.subtitleScale", selection: viewModel.subtitleScaleBinding) {
                    ForEach(viewModel.subtitleScaleOptions, id: \.self) { scale in
                        Text("settings.playback.scale \(scale)").tag(scale)
                    }
                }
                .pickerStyle(.navigationLink)
            }
        }
        .navigationTitle("settings.playback.title")
        .alert("settings.playback.player.externalWarning.title", isPresented: $showingExternalPlayerWarning) {
            Button("common.actions.done", role: .cancel) {}
        } message: {
            Text("settings.playback.player.externalWarning.message")
        }
    }
}
