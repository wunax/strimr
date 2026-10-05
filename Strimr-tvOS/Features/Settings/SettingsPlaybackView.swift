import SwiftUI

@MainActor
struct SettingsPlaybackView: View {
    @Environment(SettingsManager.self) private var settingsManager

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    var body: some View {
        SettingsList {
            Section {
                SettingsPicker(
                    "settings.playback.quality",
                    selection: viewModel.qualityPresetBinding,
                    options: Array(TranscodeQualityPreset.displayOrder),
                ) { preset in
                    Text(preset.title)
                }
                .settingsFocus("settings.playback.quality", isDefault: true)
            } footer: {
                Text("settings.playback.quality.footer")
            }

            Section {
                SettingsPicker(
                    "settings.playback.nextEpisodeAutoplay",
                    selection: viewModel.nextEpisodeAutoplayBinding,
                    options: Array(viewModel.nextEpisodeAutoplayOptions),
                ) { option in
                    Text(option.title)
                }
                .settingsFocus("settings.playback.nextEpisodeAutoplay")

                SettingsPicker(
                    "settings.playback.rewind",
                    selection: viewModel.rewindBinding,
                    options: Array(viewModel.seekOptions),
                ) { seconds in
                    Text("settings.playback.seconds \(seconds)")
                }
                .settingsFocus("settings.playback.rewind")

                SettingsPicker(
                    "settings.playback.fastForward",
                    selection: viewModel.fastForwardBinding,
                    options: Array(viewModel.seekOptions),
                ) { seconds in
                    Text("settings.playback.seconds \(seconds)")
                }
                .settingsFocus("settings.playback.fastForward")
            }

            Section {
                AudioDelaySettingsRow(settingsFocusID: "settings.playback.audioDelay")
            } footer: {
                Text("settings.playback.audioDelay.footer")
            }

            Section("settings.playback.skipping.title") {
                Toggle("settings.playback.autoSkipIntros", isOn: viewModel.autoSkipIntrosBinding)
                    .settingsFocus("settings.playback.autoSkipIntros")
                Toggle("settings.playback.autoSkipCredits", isOn: viewModel.autoSkipCreditsBinding)
                    .settingsFocus("settings.playback.autoSkipCredits")
            }

            Section("settings.playback.timeline.title") {
                Toggle(
                    "settings.playback.showChaptersOnTimeline",
                    isOn: viewModel.showChaptersOnTimelineBinding,
                )
                .settingsFocus("settings.playback.showChaptersOnTimeline")
                Toggle(
                    "settings.playback.showEndsAtTime",
                    isOn: viewModel.showEndsAtTimeBinding,
                )
                .settingsFocus("settings.playback.showEndsAtTime")
            }

            Section("settings.playback.overlay.title") {
                Toggle(
                    "settings.playback.showClock",
                    isOn: viewModel.showClockBinding,
                )
                .settingsFocus("settings.playback.showClock")
            }

            scrubThumbnailSection
        }
    }

    private var scrubThumbnailSection: some View {
        Section {
            Toggle(isOn: viewModel.showScrubThumbnailPreviewsBinding) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.playback.scrubThumbnails")
                    Text("settings.playback.scrubThumbnails.description")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsFocus("settings.playback.scrubThumbnails")

            Toggle(isOn: viewModel.generateMissingScrubThumbnailPreviewsBinding) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.playback.generateMissingScrubThumbnails")
                    Text("settings.playback.generateMissingScrubThumbnails.description")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsFocus("settings.playback.generateMissingScrubThumbnails")
            .disabled(!viewModel.showsScrubThumbnailPreviews)
        }
    }
}
