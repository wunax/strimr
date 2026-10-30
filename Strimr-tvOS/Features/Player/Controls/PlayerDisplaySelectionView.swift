import SwiftUI

struct PlayerDisplaySelectionView: View {
    var zoom: VideoZoom
    var fillScale: Double
    var onSelect: (VideoZoom) -> Void
    var onShowZoom: () -> Void

    var body: some View {
        PlayerSettingsOptionsView(
            title: "player.settings.display",
            options: options,
            parentTitle: "settings.title",
        )
    }

    private var options: [PlayerSettingsOption] {
        var options = [option(for: .fit)]
        if showsFill {
            options.append(option(for: .fill))
        }
        options.append(PlayerSettingsOption(
            id: "zoom",
            title: String(localized: "player.settings.display.zoom"),
            subtitle: zoom.persistedMode == nil ? zoom.feedbackTitle(fillScale: fillScale) : nil,
            highlightsSubtitle: true,
            isSelected: zoom.persistedMode == nil,
            action: onShowZoom,
        ))
        return options
    }

    private func option(for mode: PlayerVideoScaleMode) -> PlayerSettingsOption {
        PlayerSettingsOption(
            id: mode.rawValue,
            title: mode.feedbackTitle,
            // Without a distinct fill, a remembered fill shows as the fitted picture it renders.
            isSelected: zoom.persistedMode == mode || (mode == .fit && zoom == .fill && !showsFill),
            action: { onSelect(VideoZoom(mode)) },
        )
    }

    /// Fill only differs from the fitted picture when the video and screen shapes differ.
    private var showsFill: Bool {
        fillScale > 1.01
    }
}
