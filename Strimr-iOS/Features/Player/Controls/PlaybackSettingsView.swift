import SwiftUI

struct PlaybackSettingsView: View {
    var audioTracks: [PlaybackSettingsTrack]
    var subtitleTracks: [PlaybackSettingsTrack]
    var selectedAudioTrackID: Int?
    var selectedSubtitleTrackID: Int?
    var playbackRate: Float
    var quality: TranscodeQualityPreset
    var showsQualitySelection: Bool
    var versions: [PlaybackSettingsVersion] = []
    var onSelectVersion: (String) -> Void = { _ in }
    var onSelectAudio: (Int?) -> Void
    var onSelectSubtitle: (Int?) -> Void
    var onSearchSubtitles: (() -> Void)?
    var onResetTrackSelections: (() -> Void)?
    var onSelectPlaybackRate: (Float) -> Void
    var onSelectQuality: (TranscodeQualityPreset) -> Void
    var syncItems: [PlaybackOffsetMenuItem] = []
    var onSelectSync: (PlaybackOffsetKind) -> Void = { _ in }
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if !versions.isEmpty {
                    Section("player.settings.version") {
                        ForEach(versions) { version in
                            TrackSelectionRow(
                                title: version.title,
                                subtitle: version.subtitle,
                                isSelected: version.isSelected,
                            ) {
                                onSelectVersion(version.id)
                            }
                            .disabled(!version.isAvailable)
                        }
                    }
                }

                if showsQualitySelection {
                    Section("player.settings.quality") {
                        Picker(
                            "player.settings.quality",
                            selection: Binding(
                                get: { quality },
                                set: { onSelectQuality($0) },
                            ),
                        ) {
                            ForEach(TranscodeQualityPreset.displayOrder) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("player.settings.audio") {
                    if audioTracks.isEmpty {
                        Text("player.settings.audio.empty")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(audioTracks) { track in
                        TrackSelectionRow(
                            title: track.title,
                            subtitle: track.subtitle,
                            isSelected: selectedAudioTrackID == track.id,
                        ) {
                            onSelectAudio(track.track.id)
                        }
                    }
                }

                Section("player.settings.subtitles") {
                    TrackSelectionRow(
                        title: String(localized: "player.settings.subtitles.off"),
                        subtitle: String(localized: "player.settings.subtitles.offDescription"),
                        isSelected: selectedSubtitleTrackID == nil,
                    ) {
                        onSelectSubtitle(nil)
                    }

                    ForEach(subtitleTracks) { track in
                        TrackSelectionRow(
                            title: track.title,
                            subtitle: track.subtitle,
                            isSelected: selectedSubtitleTrackID == track.id,
                        ) {
                            onSelectSubtitle(track.track.id)
                        }
                    }

                    if let onSearchSubtitles {
                        Button(action: onSearchSubtitles) {
                            Label("subtitles.search.action", systemImage: "magnifyingglass")
                        }
                        .tint(.secondary)
                    }
                }

                if !syncItems.isEmpty {
                    Section("player.settings.sync") {
                        ForEach(syncItems) { item in
                            PlaybackOffsetMenuRow(item: item) {
                                onSelectSync(item.kind)
                            }
                        }
                    }
                }

                Section {
                    Picker(
                        "player.settings.speed",
                        selection: Binding(
                            get: { playbackRate },
                            set: { onSelectPlaybackRate($0) },
                        ),
                    ) {
                        ForEach(PlaybackSpeedOptions.all) { option in
                            Text("player.settings.speed.value \(option.valueText)")
                                .tag(option.rate)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let onResetTrackSelections {
                    Section {
                        Button("player.settings.tracks.reset", action: onResetTrackSelections)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("settings.playback.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.actions.done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct PlaybackOffsetMenuRow: View {
    let item: PlaybackOffsetMenuItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(item.kind.title, systemImage: item.kind.systemImage)
                        .foregroundStyle(.primary)
                    if let message = item.availability.message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text(item.value)
                    .monospacedDigit()
                    .fontWeight(item.isActive ? .semibold : .regular)
                    .foregroundStyle(item.isActive ? Color.brandPrimary : .secondary)
            }
        }
        .disabled(!item.availability.isAvailable)
    }
}
