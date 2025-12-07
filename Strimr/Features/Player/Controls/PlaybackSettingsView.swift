import SwiftUI

struct PlaybackSettingsView: View {
    var audioTracks: [MPVTrack]
    var subtitleTracks: [MPVTrack]
    var selectedAudioTrackID: Int?
    var selectedSubtitleTrackID: Int?
    var onSelectAudio: (Int?) -> Void
    var onSelectSubtitle: (Int?) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Audio") {
                    if audioTracks.isEmpty {
                        Text("No audio tracks available")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(audioTracks) { track in
                        TrackSelectionRow(
                            title: track.displayName,
                            subtitle: track.codec?.uppercased(),
                            isSelected: selectedAudioTrackID == track.id
                        ) {
                            onSelectAudio(track.id)
                        }
                    }
                }

                Section("Subtitles") {
                    TrackSelectionRow(
                        title: "Off",
                        subtitle: "Disable subtitles",
                        isSelected: selectedSubtitleTrackID == nil
                    ) {
                        onSelectSubtitle(nil)
                    }

                    ForEach(subtitleTracks) { track in
                        TrackSelectionRow(
                            title: track.displayName,
                            subtitle: track.codec?.uppercased(),
                            isSelected: selectedSubtitleTrackID == track.id
                        ) {
                            onSelectSubtitle(track.id)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Playback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct TrackSelectionRow: View {
    var title: String
    var subtitle: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
    }
}
