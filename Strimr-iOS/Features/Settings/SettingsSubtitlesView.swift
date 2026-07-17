import SwiftUI

@MainActor
struct SettingsSubtitlesView: View {
    @Environment(SettingsManager.self) private var settingsManager

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    var body: some View {
        List {
            Section("settings.playback.subtitles.preview.title") {
                SubtitleAppearancePreview(appearance: settingsManager.playback.subtitleAppearance)
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Picker("settings.playback.subtitleFontSize", selection: viewModel.subtitleFontSizeBinding) {
                    ForEach(viewModel.subtitleFontSizeOptions, id: \.self) { fontSize in
                        Text("settings.playback.fontSize \(fontSize)").tag(fontSize)
                    }
                }

                Picker("settings.playback.subtitles.color", selection: viewModel.subtitleTextColorBinding) {
                    ForEach(viewModel.subtitleTextColorOptions, id: \.self) { color in
                        Text(color.localizedName).tag(color)
                    }
                }

                Picker("settings.playback.subtitles.weight", selection: viewModel.subtitleFontWeightBinding) {
                    ForEach(viewModel.subtitleFontWeightOptions, id: \.self) { weight in
                        Text(weight.localizedName).tag(weight)
                    }
                }

                Picker(
                    "settings.playback.subtitles.background",
                    selection: viewModel.subtitleBackgroundStrengthBinding,
                ) {
                    ForEach(viewModel.subtitleBackgroundStrengthOptions, id: \.self) { strength in
                        Text(strength.localizedName).tag(strength)
                    }
                }

                Picker(
                    "settings.playback.subtitles.edge",
                    selection: viewModel.subtitleEdgeStyleBinding,
                ) {
                    ForEach(viewModel.subtitleEdgeStyleOptions, id: \.self) { style in
                        Text(style.localizedName).tag(style)
                    }
                }

                Picker("settings.playback.subtitles.position", selection: viewModel.subtitleVerticalPositionBinding) {
                    ForEach(viewModel.subtitleVerticalPositionOptions, id: \.self) { position in
                        Text(position.localizedName).tag(position)
                    }
                }
            } footer: {
                Text("settings.playback.subtitles.footer")
            }

            Section {
                Button("settings.playback.subtitles.reset") {
                    viewModel.resetSubtitleAppearance()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("settings.playback.subtitles.title")
    }
}
