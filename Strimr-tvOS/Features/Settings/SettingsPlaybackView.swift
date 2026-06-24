import SwiftUI

@MainActor
struct SettingsPlaybackView: View {
    @Environment(SettingsManager.self) private var settingsManager

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    var body: some View {
        List {
            Section {
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

                Picker("settings.playback.subtitleScale", selection: viewModel.subtitleScaleBinding) {
                    ForEach(viewModel.subtitleScaleOptions, id: \.self) { scale in
                        Text("settings.playback.scale \(scale)").tag(scale)
                    }
                }
                .pickerStyle(.navigationLink)
            }
        }
        .navigationTitle("settings.playback.title")
    }
}
