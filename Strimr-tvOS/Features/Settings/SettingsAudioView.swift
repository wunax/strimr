import SwiftUI

@MainActor
struct SettingsAudioView: View {
    @Environment(SettingsManager.self) private var settingsManager

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    var body: some View {
        SettingsList {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("settings.playback.losslessAudio", isOn: viewModel.losslessAudioBinding)
                        .settingsFocus("settings.playback.losslessAudio", isDefault: true)
                    Text("settings.playback.losslessAudio.footer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        "settings.playback.rememberTrackSelections",
                        isOn: viewModel.rememberTrackSelectionsBinding,
                    )
                    .settingsFocus("settings.playback.rememberTrackSelections")
                    Text("settings.playback.rememberTrackSelections.footer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("settings.playback.audio.title")
            }

            Section {
                AudioDelaySettingsRow(settingsFocusID: "settings.playback.audioDelay")
            } footer: {
                Text("settings.playback.audioDelay.footer")
            }
        }
    }
}
