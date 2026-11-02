import SwiftUI

struct PlayerTrackSelectionView: View {
    var titleKey: LocalizedStringKey
    var tracks: [PlaybackSettingsTrack]
    var selectedTrackID: Int?
    var showOffOption: Bool
    var onSelect: (Int?) -> Void
    var onSearchSubtitles: (() -> Void)?
    var onResetTrackSelections: (() -> Void)?
    var syncItem: PlaybackOffsetMenuItem?
    var onSelectSync: (PlaybackOffsetKind) -> Void = { _ in }
    var audioEnhancements: PlayerAudioEnhancements?
    var initialOptionID: String?

    var body: some View {
        PlayerSettingsOptionsView(title: titleKey, options: options, initialOptionID: initialOptionID)
            .overlay {
                if tracks.isEmpty, !showOffOption {
                    Text("player.settings.audio.empty").foregroundStyle(.secondary)
                }
            }
    }

    private var options: [PlayerSettingsOption] {
        var result: [PlayerSettingsOption] = []
        if showOffOption {
            result.append(PlayerSettingsOption(
                id: "off",
                title: String(localized: "player.settings.subtitles.off"),
                subtitle: String(localized: "player.settings.subtitles.offDescription"),
                isSelected: selectedTrackID == nil,
                action: { onSelect(nil) },
            ))
        }
        result += tracks.map { track in
            PlayerSettingsOption(
                id: String(track.id), title: track.title, subtitle: track.subtitle,
                isSelected: selectedTrackID == track.id,
                action: { onSelect(track.track.id) },
            )
        }
        if let onSearchSubtitles {
            result.append(PlayerSettingsOption(
                id: "search",
                title: String(localized: "subtitles.search.action"),
                systemImage: "magnifyingglass",
                action: onSearchSubtitles,
            ))
        }
        if let onResetTrackSelections {
            result.append(PlayerSettingsOption(
                id: "reset",
                title: String(localized: "player.settings.tracks.reset"),
                systemImage: "arrow.counterclockwise",
                action: onResetTrackSelections,
            ))
        }
        if let syncItem {
            result.append(PlayerSettingsOption(
                id: "sync",
                title: syncItem.kind.title,
                subtitle: syncItem.availability.message ?? syncItem.value,
                highlightsSubtitle: syncItem.isActive && syncItem.availability.isAvailable,
                systemImage: syncItem.kind.systemImage,
                isDisabled: !syncItem.availability.isAvailable,
                opensSubmenu: true,
                sectionTitle: String(localized: "player.settings.sync"),
                action: { onSelectSync(syncItem.kind) },
            ))
        }
        if let audioEnhancements {
            result += audioEnhancements.options
        }
        return result
    }
}

struct PlayerAudioEnhancements {
    var nightMode: Bool
    var dialogueBoost: DialogueBoost
    var isAvailable: Bool
    var onToggleNightMode: () -> Void
    var onShowDialogueBoost: () -> Void

    fileprivate var options: [PlayerSettingsOption] {
        [
            PlayerSettingsOption(
                id: "nightMode",
                title: String(localized: "settings.playback.nightMode"),
                subtitle: isAvailable ? nil : String(localized: "player.settings.audioEnhancements.unavailable"),
                isSelected: nightMode,
                systemImage: "moon.stars",
                sectionTitle: String(localized: "settings.playback.audioEnhancements"),
                action: onToggleNightMode,
            ),
            PlayerSettingsOption(
                id: "dialogueBoost",
                title: String(localized: "settings.playback.dialogueBoost"),
                subtitle: dialogueBoost.title,
                highlightsSubtitle: dialogueBoost != .off,
                systemImage: "person.wave.2",
                opensSubmenu: true,
                action: onShowDialogueBoost,
            ),
        ]
    }
}
