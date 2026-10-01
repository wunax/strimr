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
            options: versionOptions + qualityOptions,
            onClose: onClose,
        )
    }

    private var qualityOptions: [PlayerSettingsOption] {
        TranscodeQualityPreset.displayOrder.enumerated().map { index, preset in
            PlayerSettingsOption(
                id: preset.rawValue, title: preset.title,
                isSelected: selectedQuality == preset,
                sectionTitle: index == 0 && onShowVersions != nil
                    ? String(localized: "player.settings.quality.streaming") : nil,
                action: { onSelect(preset) },
            )
        }
    }

    private var versionOptions: [PlayerSettingsOption] {
        guard let onShowVersions else { return [] }
        return [PlayerSettingsOption(
            id: "version",
            title: String(localized: "player.settings.version"),
            subtitle: versionLabel,
            systemImage: "film.stack",
            opensSubmenu: true,
            action: onShowVersions,
        )]
    }
}
