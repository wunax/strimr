import SwiftUI

@MainActor
struct SettingsSubtitlesView: View {
    @Environment(SettingsManager.self) private var settingsManager

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    var body: some View {
        SettingsList {
            Section {
                Toggle(
                    "settings.playback.subtitles.styledASS",
                    isOn: viewModel.styledASSSubtitlesBinding,
                )
                .settingsFocus("settings.playback.subtitles.styledASS", isDefault: true)
            } footer: {
                Text("settings.playback.subtitles.styledASS.description")
            }

            Section {
                Toggle(
                    "settings.playback.subtitles.automaticSearch",
                    isOn: viewModel.automaticSubtitleSearchBinding,
                )
                .settingsFocus("settings.playback.subtitles.automaticSearch")
            } footer: {
                Text("settings.playback.subtitles.automaticSearch.description")
            }

            Section {
                Toggle(
                    "settings.playback.subtitles.showOnSkipBack",
                    isOn: viewModel.showSubtitlesOnSkipBackBinding,
                )
                .settingsFocus("settings.playback.subtitles.showOnSkipBack")
            } footer: {
                Text("settings.playback.subtitles.showOnSkipBack.description")
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

            if viewModel.showsSubtitleBottomMargin {
                Section {
                    SettingsPicker(
                        "settings.playback.subtitles.bottomMargin",
                        selection: viewModel.subtitleBottomMarginBinding,
                        options: Array(viewModel.subtitleBottomMarginOptions),
                    ) { margin in
                        Text(margin.localizedName)
                    }
                    .settingsFocus("settings.playback.subtitles.bottomMargin")
                } footer: {
                    Text("settings.playback.subtitles.bottomMargin.description")
                }
            }

            Section {
                SettingsPicker(
                    "settings.playback.subtitles.brightness",
                    selection: viewModel.subtitleBrightnessBinding,
                    options: Array(viewModel.subtitleBrightnessOptions),
                ) { brightness in
                    Text(brightness.localizedName)
                }
                .settingsFocus("settings.playback.subtitles.brightness")
            } footer: {
                Text("settings.playback.subtitles.brightness.description")
            }

            Section {
                Button("settings.playback.subtitles.reset") {
                    viewModel.resetSubtitleAppearance()
                }
                .settingsFocus("resetSubtitles")
            }
        }
    }
}
