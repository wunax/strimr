import SwiftUI

struct PlayerTrackSelectionView: View {
    var titleKey: LocalizedStringKey
    var tracks: [PlaybackSettingsTrack]
    var selectedTrackID: Int?
    var showOffOption: Bool
    var onSelect: (Int?) -> Void
    var onSearchSubtitles: (() -> Void)?
    var onResetTrackSelections: (() -> Void)?
    var onClose: () -> Void

    var body: some View {
        PlayerSettingsOptionsView(title: titleKey, options: options, onClose: onClose)
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
        return result
    }
}
