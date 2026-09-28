import SwiftUI

@MainActor
struct SettingsSubtitlesView: View {
    @Environment(SettingsManager.self) private var settingsManager

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    var body: some View {
        List {
            Section {
                Toggle(
                    "settings.playback.subtitles.styledASS",
                    isOn: viewModel.styledASSSubtitlesBinding,
                )
                .settingsFocus("settings.playback.subtitles.styledASS", isDefault: true)
            } footer: {
                Text("settings.playback.subtitles.styledASS.description")
            }

            Section("settings.playback.subtitles.preview.title") {
                SubtitleAppearancePreview(appearance: settingsManager.playback.subtitleAppearance)
                    .frame(height: 180)
            }

            Section {
                SettingsPicker(
                    "settings.playback.subtitleFontSize",
                    selection: viewModel.subtitleFontSizeBinding,
                    options: Array(viewModel.subtitleFontSizeOptions),
                ) { fontSize in
                    Text("settings.playback.fontSize \(fontSize)")
                }
                .settingsFocus("settings.playback.subtitleFontSize")

                SettingsPicker(
                    "settings.playback.subtitles.color",
                    selection: viewModel.subtitleTextColorBinding,
                    options: Array(viewModel.subtitleTextColorOptions),
                ) { color in
                    Text(color.localizedName)
                }
                .settingsFocus("settings.playback.subtitles.color")

                SettingsPicker(
                    "settings.playback.subtitles.weight",
                    selection: viewModel.subtitleFontWeightBinding,
                    options: Array(viewModel.subtitleFontWeightOptions),
                ) { weight in
                    Text(weight.localizedName)
                }
                .settingsFocus("settings.playback.subtitles.weight")

                SettingsPicker(
                    "settings.playback.subtitles.background",
                    selection: viewModel.subtitleBackgroundStrengthBinding,
                    options: Array(viewModel.subtitleBackgroundStrengthOptions),
                ) { strength in
                    Text(strength.localizedName)
                }
                .settingsFocus("settings.playback.subtitles.background")

                SettingsPicker(
                    "settings.playback.subtitles.edge",
                    selection: viewModel.subtitleEdgeStyleBinding,
                    options: Array(viewModel.subtitleEdgeStyleOptions),
                ) { style in
                    Text(style.localizedName)
                }
                .settingsFocus("settings.playback.subtitles.edge")

                SettingsPicker(
                    "settings.playback.subtitles.position",
                    selection: viewModel.subtitleVerticalPositionBinding,
                    options: Array(viewModel.subtitleVerticalPositionOptions),
                ) { position in
                    Text(position.localizedName)
                }
                .settingsFocus("settings.playback.subtitles.position")
            } footer: {
                Text("settings.playback.subtitles.footer")
            }

            Section {
                Button("settings.playback.subtitles.reset") {
                    viewModel.resetSubtitleAppearance()
                }
                .settingsFocus("resetSubtitles")
            }
        }
        .listStyle(.plain)
    }
}
