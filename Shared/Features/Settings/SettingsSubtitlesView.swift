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
            } footer: {
                Text("settings.playback.subtitles.styledASS.description")
            }

            Section {
                Toggle(
                    "settings.playback.subtitles.showOnSkipBack",
                    isOn: viewModel.showSubtitlesOnSkipBackBinding,
                )
            } footer: {
                Text("settings.playback.subtitles.showOnSkipBack.description")
            }

            Section("settings.playback.subtitles.preview.title") {
                SubtitleAppearancePreview(appearance: settingsManager.playback.subtitleAppearance)
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
            }

            SubtitleAppearanceSections()
        }
        .insetListStyle()
        .navigationTitle("settings.playback.subtitles.title")
    }
}

/// The appearance settings, shared by the settings screen and the player.
@MainActor
struct SubtitleAppearanceSections: View {
    var availability = SubtitleAppearanceAvailability.available
    var showsDescriptions = true

    @Environment(SettingsManager.self) private var settingsManager

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    var body: some View {
        let viewModel = viewModel

        Section {
            Group {
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
            }
            .disabled(!availability.allowsTextStyling)
        } footer: {
            if showsDescriptions || !availability.allowsTextStyling {
                Text("settings.playback.subtitles.footer")
            }
        }

        if viewModel.showsSubtitleBottomMargin {
            Section {
                Picker(
                    "settings.playback.subtitles.bottomMargin",
                    selection: viewModel.subtitleBottomMarginBinding,
                ) {
                    ForEach(viewModel.subtitleBottomMarginOptions, id: \.self) { margin in
                        Text(margin.localizedName).tag(margin)
                    }
                }
            } footer: {
                if showsDescriptions {
                    Text("settings.playback.subtitles.bottomMargin.description")
                }
            }
        }

        Section {
            Picker("settings.playback.subtitles.brightness", selection: viewModel.subtitleBrightnessBinding) {
                ForEach(viewModel.subtitleBrightnessOptions, id: \.self) { brightness in
                    Text(brightness.localizedName).tag(brightness)
                }
            }
        } footer: {
            if showsDescriptions {
                Text("settings.playback.subtitles.brightness.description")
            }
        }

        Section {
            Button("settings.playback.subtitles.reset") {
                viewModel.resetSubtitleAppearance()
            }
        }
    }
}
