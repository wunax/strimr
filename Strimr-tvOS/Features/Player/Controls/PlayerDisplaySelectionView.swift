import SwiftUI

struct PlayerDisplaySelectionView: View {
    var zoom: VideoZoom
    var fillScale: Double
    var onSelect: (VideoZoom) -> Void

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

        let maximumScale = VideoZoom.maximumScale(fillScale: fillScale)
        let presets = VideoZoom.presetScales.filter { $0 <= maximumScale + 0.001 }
        for (index, scale) in presets.enumerated() {
            let isRemoveBars = scale == VideoZoom.removeBarsScale
            options.append(PlayerSettingsOption(
                id: "zoom-\(scale)",
                title: VideoZoom.percentText(scale: scale),
                subtitle: isRemoveBars ? String(localized: "player.settings.display.removeBars") : nil,
                isSelected: isSelected(scale),
                sectionTitle: index == 0 ? String(localized: "player.settings.display.zoom") : nil,
                action: { onSelect(.custom(scale)) },
            ))
        }
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

    private func isSelected(_ scale: Double) -> Bool {
        guard case let .custom(current) = zoom else { return false }
        return abs(current - scale) < 0.001
    }
}
