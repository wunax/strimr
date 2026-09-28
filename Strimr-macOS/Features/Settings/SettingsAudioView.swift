import SwiftUI

@MainActor
struct SettingsAudioView: View {
    @Environment(SettingsManager.self) private var settingsManager

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("settings.playback.losslessAudio", isOn: viewModel.losslessAudioBinding)
                    Text("settings.playback.losslessAudio.footer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "settings.playback.rememberTrackSelections",
                        isOn: viewModel.rememberTrackSelectionsBinding,
                    )
                    Text("settings.playback.rememberTrackSelections.footer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("settings.playback.audio.title")
            }
        }
        .listStyle(.inset)
        .navigationTitle("settings.playback.audio.title")
    }
}
