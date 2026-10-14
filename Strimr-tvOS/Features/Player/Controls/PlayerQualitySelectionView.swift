import SwiftUI

struct PlayerQualitySelectionView: View {
    var selectedQuality: TranscodeQualityPreset
    var onSelect: (TranscodeQualityPreset) -> Void

    var body: some View {
        PlayerSettingsOptionsView(
            title: "player.settings.quality",
            options: TranscodeQualityPreset.displayOrder.map { preset in
                PlayerSettingsOption(
                    id: preset.rawValue,
                    title: preset.title,
                    isSelected: selectedQuality == preset,
                    action: { onSelect(preset) },
                )
            },
            parentTitle: "settings.title",
        )
    }
}
