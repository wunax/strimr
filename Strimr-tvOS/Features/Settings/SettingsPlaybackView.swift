import SwiftUI

@MainActor
struct SettingsPlaybackView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SettingsNavigation.self) private var navigation

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    var body: some View {
        SettingsList {
            externalPlayerSection

            Section {
                SettingsPicker(
                    "settings.playback.quality",
                    selection: viewModel.qualityPresetBinding,
                    options: Array(TranscodeQualityPreset.displayOrder),
                ) { preset in
                    Text(preset.title)
                }
                .settingsFocus("settings.playback.quality")
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
                Toggle(isOn: viewModel.showInfoWhenPausedBinding) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.playback.showInfoWhenPaused")
                        Text("settings.playback.showInfoWhenPaused.description")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsFocus("settings.playback.showInfoWhenPaused")
            }

            scrubThumbnailSection
        }
    }

    private var externalPlayerSection: some View {
        Section {
            Button {
                navigation.push("settings.playback.externalPlayer.title") {
                    ExternalPlayerOptionsView(viewModel: viewModel)
                }
            } label: {
                HStack(spacing: 20) {
                    Text("settings.playback.externalPlayer.title")
                    Spacer(minLength: 16)
                    Text(viewModel.title(for: viewModel.selectedExternalPlayerOption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .settingsFocus("settings.playback.externalPlayer", isDefault: true)

            if let customPlayer = viewModel.customExternalPlayer {
                Button("settings.playback.externalPlayer.custom.edit") {
                    navigation.push("settings.playback.externalPlayer.custom.title") {
                        CustomExternalPlayerView(player: customPlayer) { player in
                            viewModel.saveCustomExternalPlayer(player)
                        }
                    }
                }
                .settingsFocus("settings.playback.externalPlayer.custom.edit")
            }
        } footer: {
            if let footer = viewModel.externalPlayerFooter {
                Text(footer)
            }
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
