import SwiftUI

struct PlayerQualitySelectionView: View {
    var selectedQuality: TranscodeQualityPreset
    var versionLabel: String?
    var onShowVersions: (() -> Void)?
    var onSelect: (TranscodeQualityPreset) -> Void

    var onClose: () -> Void

    var body: some View {
        PlayerSettingsOptionsView(
            title: "player.settings.quality",
            options: versionOptions + TranscodeQualityPreset.displayOrder.map { preset in
                PlayerSettingsOption(
                    id: preset.rawValue, title: preset.title,
                    isSelected: selectedQuality == preset,
                    action: { onSelect(preset) },
                )
            },
            onClose: onClose,
        )
    }

    private var versionOptions: [PlayerSettingsOption] {
        guard let onShowVersions else { return [] }
        return [PlayerSettingsOption(
            id: "version",
            title: String(localized: "player.settings.version"),
            subtitle: versionLabel,
            systemImage: "square.stack",
            action: onShowVersions,
        )]
    }
}
