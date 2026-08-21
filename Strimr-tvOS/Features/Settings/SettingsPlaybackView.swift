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
                Picker(
                    "settings.playback.nextEpisodeAutoplay",
                    selection: viewModel.nextEpisodeAutoplayBinding,
                ) {
                    ForEach(viewModel.nextEpisodeAutoplayOptions, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("settings.playback.rewind", selection: viewModel.rewindBinding) {
                    ForEach(viewModel.seekOptions, id: \.self) { seconds in
                        Text("settings.playback.seconds \(seconds)").tag(seconds)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("settings.playback.fastForward", selection: viewModel.fastForwardBinding) {
                    ForEach(viewModel.seekOptions, id: \.self) { seconds in
                        Text("settings.playback.seconds \(seconds)").tag(seconds)
                    }
                }
                .pickerStyle(.navigationLink)
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

            Section("settings.playback.overlay.title") {
                Toggle(
                    "settings.playback.showClock",
                    isOn: viewModel.showClockBinding,
                )
            }

            scrubThumbnailSection

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
        .navigationTitle("settings.playback.title")
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

            Toggle(isOn: viewModel.generateMissingScrubThumbnailPreviewsBinding) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.playback.generateMissingScrubThumbnails")
                    Text("settings.playback.generateMissingScrubThumbnails.description")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!viewModel.showsScrubThumbnailPreviews)
        }
    }
}
