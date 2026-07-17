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

                Picker("settings.playback.fastForward", selection: viewModel.fastForwardBinding) {
                    ForEach(viewModel.seekOptions, id: \.self) { seconds in
                        Text("settings.playback.seconds \(seconds)").tag(seconds)
                    }
                }
            }

            Section("settings.playback.subtitles.title") {
                NavigationLink("settings.playback.subtitles.customize") {
                    SettingsSubtitlesView()
                }
            }

            Section {
                Toggle("settings.playback.losslessAudio", isOn: viewModel.losslessAudioBinding)
            } header: {
                Text("settings.playback.audio.title")
            } footer: {
                Text("settings.playback.losslessAudio.footer")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("settings.playback.title")
    }
}
