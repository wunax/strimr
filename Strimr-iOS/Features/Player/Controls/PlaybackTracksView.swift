import SwiftUI

struct PlaybackTracksView: View {
    var audioTracks: [PlaybackSettingsTrack]
    var subtitleTracks: [PlaybackSettingsTrack]
    var selectedAudioTrackID: Int?
    var selectedSubtitleTrackID: Int?
    var onSelectAudio: (Int?) -> Void
    var onSelectSubtitle: (Int?) -> Void
    var nightMode = false
    var dialogueBoost = DialogueBoost.off
    var isAudioShapingAvailable = true
    var onSetNightMode: (Bool) -> Void = { _ in }
    var onSelectDialogueBoost: (DialogueBoost) -> Void = { _ in }
    var onSearchSubtitles: (() -> Void)?
    var onResetTrackSelections: (() -> Void)?
    var syncItems: [PlaybackOffsetMenuItem] = []
    var onSelectSync: (PlaybackOffsetKind) -> Void = { _ in }
    var onClose: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        NavigationStack {
            Group {
                if verticalSizeClass == .compact {
                    HStack(spacing: 0) {
                        List { audioSections }
                        List {
                            subtitleSections
                            resetSection
                        }
                    }
                } else {
                    List {
                        audioSections
                        subtitleSections
                        resetSection
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("player.tracks.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.actions.done", action: onClose)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var audioSections: some View {
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

            syncRow(for: .audio)
        }

        Section {
            Toggle(isOn: Binding(get: { nightMode }, set: { onSetNightMode($0) })) {
                Label("settings.playback.nightMode", systemImage: "moon.stars")
            }

            Picker(
                selection: Binding(get: { dialogueBoost }, set: { onSelectDialogueBoost($0) }),
            ) {
                ForEach(DialogueBoost.allCases) { boost in
                    Text(boost.title).tag(boost)
                }
            } label: {
                Label("settings.playback.dialogueBoost", systemImage: "person.wave.2")
            }
            .pickerStyle(.menu)
        } header: {
            Text("settings.playback.audioEnhancements")
        } footer: {
            if !isAudioShapingAvailable {
                Text("player.settings.audioEnhancements.unavailable")
            }
        }
    }

    private var subtitleSections: some View {
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

            syncRow(for: .subtitles)

            if let onSearchSubtitles {
                Button(action: onSearchSubtitles) {
                    Label("subtitles.search.action", systemImage: "magnifyingglass")
                }
                .tint(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        if let onResetTrackSelections {
            Section {
                Button("player.settings.tracks.reset", action: onResetTrackSelections)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func syncRow(for kind: PlaybackOffsetKind) -> some View {
        if let item = syncItems.first(where: { $0.kind == kind }) {
            PlaybackOffsetMenuRow(item: item) {
                onSelectSync(item.kind)
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
                    .foregroundStyle(item.isActive ? Color.selectionAccent : .secondary)
            }
        }
        .disabled(!item.availability.isAvailable)
    }
}
