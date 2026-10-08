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
                Picker("settings.playback.quality", selection: viewModel.qualityPresetBinding) {
                    ForEach(TranscodeQualityPreset.displayOrder) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
            } footer: {
                Text("settings.playback.quality.footer")
            }

            Section {
                Picker(
                    "settings.playback.nextEpisodeAutoplay",
                    selection: viewModel.nextEpisodeAutoplayBinding,
                ) {
                    ForEach(viewModel.nextEpisodeAutoplayOptions, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }

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

            Section("settings.playback.skipping.title") {
                Toggle("settings.playback.autoSkipIntros", isOn: viewModel.autoSkipIntrosBinding)
                Toggle("settings.playback.autoSkipCredits", isOn: viewModel.autoSkipCreditsBinding)
            }

            Section("settings.playback.timeline.title") {
                Toggle(
                    "settings.playback.showChaptersOnTimeline",
                    isOn: viewModel.showChaptersOnTimelineBinding,
                )
                Toggle(
                    "settings.playback.showEndsAtTime",
                    isOn: viewModel.showEndsAtTimeBinding,
                )
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "settings.playback.showInfoWhenPaused",
                        isOn: viewModel.showInfoWhenPausedBinding,
                    )
                    Text("settings.playback.showInfoWhenPaused.description")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            scrubThumbnailSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("settings.playback.title")
    }

    private var scrubThumbnailSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    "settings.playback.scrubThumbnails",
                    isOn: viewModel.showScrubThumbnailPreviewsBinding,
                )
                Text("settings.playback.scrubThumbnails.description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    "settings.playback.generateMissingScrubThumbnails",
                    isOn: viewModel.generateMissingScrubThumbnailPreviewsBinding,
                )
                Text("settings.playback.generateMissingScrubThumbnails.description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .disabled(!viewModel.showsScrubThumbnailPreviews)
        }
    }
}
