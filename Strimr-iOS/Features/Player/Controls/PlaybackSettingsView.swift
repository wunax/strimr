import SwiftUI

struct PlaybackSettingsView: View {
    var audioTracks: [PlaybackSettingsTrack]
    var subtitleTracks: [PlaybackSettingsTrack]
    var selectedAudioTrackID: Int?
    var selectedSubtitleTrackID: Int?
    var playbackRate: Float
    var onSelectAudio: (Int?) -> Void
    var onSelectSubtitle: (Int?) -> Void
    var onSelectPlaybackRate: (Float) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
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
                }

                Section {
                    Picker(
                        "player.settings.speed",
                        selection: Binding(
                            get: { playbackRate },
                            set: { onSelectPlaybackRate($0) }
                        )
                    ) {
                        ForEach(PlaybackSpeedOptions.all) { option in
                            Text("player.settings.speed.value \(option.valueText)")
                                .tag(option.rate)
                        }
                    }
                    .pickerStyle(.menu)
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
