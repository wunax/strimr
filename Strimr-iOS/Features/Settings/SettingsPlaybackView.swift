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
                Toggle("settings.playback.autoPlayNext", isOn: viewModel.autoPlayNextBinding)

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
