import SwiftUI

@MainActor
struct SettingsPlaybackView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(ServerRegistry.self) private var registry
    @State private var isEditingCustomPlayer = false

    private var viewModel: SettingsViewModel {
        SettingsViewModel(settingsManager: settingsManager)
    }

    /// Commercial markers come from DVR recordings in practice, so the setting stays hidden without Live TV.
    private var hasLiveTV: Bool {
        !registry.liveTVServices.isEmpty
    }

    var body: some View {
        List {
            externalPlayerSection

            if UIDevice.current.userInterfaceIdiom == .phone {
                Section {
                    Toggle("settings.playback.autoRotateVideo", isOn: viewModel.autoRotateVideoBinding)
                } footer: {
                    Text("settings.playback.autoRotateVideo.description")
                }
            }

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

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("settings.playback.doubleTapToSeek", isOn: viewModel.doubleTapToSeekBinding)
                    Text("settings.playback.doubleTapToSeek.description")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("settings.playback.autoSkipIntros", isOn: viewModel.autoSkipIntrosBinding)
                Toggle("settings.playback.autoSkipCredits", isOn: viewModel.autoSkipCreditsBinding)
                if hasLiveTV {
                    Toggle("settings.playback.autoSkipCommercials", isOn: viewModel.autoSkipCommercialsBinding)
                }
            } header: {
                Text("settings.playback.skipping.title")
            } footer: {
                if hasLiveTV {
                    Text("settings.playback.autoSkipCommercials.footer")
                }
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
        .navigationDestination(isPresented: $isEditingCustomPlayer) {
            CustomExternalPlayerView(player: viewModel.customExternalPlayer) { player in
                viewModel.saveCustomExternalPlayer(player)
            }
        }
    }

    private var externalPlayerSection: some View {
        Section {
            Picker("settings.playback.externalPlayer.title", selection: externalPlayerBinding) {
                ForEach(viewModel.externalPlayerOptions) { option in
                    Text(viewModel.title(for: option)).tag(option)
                }
            }

            if viewModel.customExternalPlayer != nil {
                Button("settings.playback.externalPlayer.custom.edit") {
                    isEditingCustomPlayer = true
                }
            }
        } footer: {
            if let footer = viewModel.externalPlayerFooter {
                Text(footer)
            }
        }
    }

    private var externalPlayerBinding: Binding<ExternalPlayerOption> {
        Binding(
            get: { viewModel.selectedExternalPlayerOption },
            set: { option in
                if !viewModel.selectExternalPlayer(option) {
                    isEditingCustomPlayer = true
                }
            },
        )
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
