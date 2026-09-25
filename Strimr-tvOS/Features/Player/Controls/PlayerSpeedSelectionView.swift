import SwiftUI

struct PlayerSpeedSelectionView: View {
    var selectedRate: Float
    var onSelect: (Float) -> Void
    var onClose: () -> Void

    var body: some View {
        PlayerSettingsOptionsView(title: "player.settings.speed", options: PlaybackSpeedOptions.all.map { option in
            PlayerSettingsOption(
                id: option.valueText,
                title: String(localized: "player.settings.speed.value \(option.valueText)"),
                isSelected: abs(selectedRate - option.rate) < 0.001,
                action: { onSelect(option.rate) },
            )
        }, onClose: onClose)
    }
}
