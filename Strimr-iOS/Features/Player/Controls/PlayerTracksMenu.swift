import SwiftUI

struct PlayerTracksMenuModel: Equatable {
    var audioTracks: [PlaybackSettingsTrack]
    var subtitleTracks: [PlaybackSettingsTrack]
    var selectedAudioTrackID: Int?
    var selectedSubtitleTrackID: Int?
    var nightMode: Bool
    var dialogueBoost: DialogueBoost
    var isAudioShapingAvailable: Bool
    var canSearchSubtitles: Bool
    var canResetTrackSelections: Bool
    var syncItems: [PlaybackOffsetMenuItem]

    var showsIndicator: Bool {
        syncItems.contains { $0.kind == .subtitles && $0.isActive }
    }
}

struct PlayerTracksMenuActions {
    var onPresentationChanged: (Bool) -> Void
    var onSelectAudio: (Int?) -> Void
    var onSelectSubtitle: (Int?) -> Void
    var onSetNightMode: (Bool) -> Void
    var onSelectDialogueBoost: (DialogueBoost) -> Void
    var onSearchSubtitles: () -> Void
    var onResetTrackSelections: () -> Void
    var onSelectSync: (PlaybackOffsetKind) -> Void
}

/// Compares the model only, so that the playback position refreshing the player does not rebuild an open menu.
struct PlayerTracksMenu<MenuLabel: View>: View, Equatable {
    let model: PlayerTracksMenuModel
    let actions: PlayerTracksMenuActions
    @ViewBuilder let label: () -> MenuLabel

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model == rhs.model
    }

    var body: some View {
        Menu {
            Group {
                audioMenu
                subtitlesMenu
                if model.canResetTrackSelections {
                    Section {
                        Button(action: actions.onResetTrackSelections) {
                            Label("player.settings.tracks.reset", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
            }
            // SwiftUI exposes no open state for a menu, but its content appears and disappears with it.
            .onAppear { actions.onPresentationChanged(true) }
            .onDisappear { actions.onPresentationChanged(false) }
        } label: {
            label()
        }
        .menuOrder(.fixed)
        .onDisappear { actions.onPresentationChanged(false) }
    }

    private var audioMenu: some View {
        Menu {
            if model.audioTracks.isEmpty {
                Text("player.settings.audio.empty")
            }

            ForEach(model.audioTracks) { track in
                trackOption(track, isSelected: model.selectedAudioTrackID == track.id) {
                    actions.onSelectAudio(track.track.id)
                }
            }

            syncButton(for: .audio)

            Section {
                Toggle(isOn: Binding(get: { model.nightMode }, set: { actions.onSetNightMode($0) })) {
                    Text("settings.playback.nightMode")
                }

                Picker(selection: Binding(get: { model.dialogueBoost }, set: { actions.onSelectDialogueBoost($0) })) {
                    ForEach(DialogueBoost.allCases) { boost in
                        Text(boost.title).tag(boost)
                    }
                } label: {
                    Text("settings.playback.dialogueBoost")
                }
                .pickerStyle(.menu)
            } header: {
                if model.isAudioShapingAvailable {
                    Text("settings.playback.audioEnhancements")
                } else {
                    Text("player.settings.audioEnhancements.unavailable")
                }
            }
        } label: {
            Label {
                Text("player.settings.audio")
                if let title = model.audioTracks.first(where: { $0.id == model.selectedAudioTrackID })?.title {
                    Text(title)
                }
            } icon: {
                Image(systemName: "waveform")
            }
        }
    }

    private var subtitlesMenu: some View {
        Menu {
            Toggle(isOn: Binding(
                get: { model.selectedSubtitleTrackID == nil },
                set: { _ in actions.onSelectSubtitle(nil) },
            )) {
                Text("player.settings.subtitles.off")
            }

            ForEach(model.subtitleTracks) { track in
                trackOption(track, isSelected: model.selectedSubtitleTrackID == track.id) {
                    actions.onSelectSubtitle(track.track.id)
                }
            }

            syncButton(for: .subtitles)

            if model.canSearchSubtitles {
                Section {
                    Button("subtitles.search.action", action: actions.onSearchSubtitles)
                }
            }
        } label: {
            Label {
                Text("player.settings.subtitles")
                if let title = model.subtitleTracks.first(where: { $0.id == model.selectedSubtitleTrackID })?.title {
                    Text(title)
                } else {
                    Text("player.settings.subtitles.off")
                }
            } icon: {
                Image(systemName: "captions.bubble")
            }
        }
    }

    private func trackOption(
        _ track: PlaybackSettingsTrack,
        isSelected: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in action() })) {
            Text(track.title)
            if let subtitle = track.subtitle {
                Text(subtitle)
            }
        }
    }

    @ViewBuilder
    private func syncButton(for kind: PlaybackOffsetKind) -> some View {
        if let item = model.syncItems.first(where: { $0.kind == kind }) {
            Section {
                Button {
                    actions.onSelectSync(kind)
                } label: {
                    Text(item.kind.title)
                    Text(item.availability.message ?? item.value)
                }
                .disabled(!item.availability.isAvailable)
            }
        }
    }
}
