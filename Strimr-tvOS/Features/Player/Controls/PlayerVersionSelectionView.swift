import SwiftUI

struct PlayerVersionSelectionView: View {
    var versions: [PlaybackSettingsVersion]
    var onSelect: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        PlayerSettingsOptionsView(
            title: "player.settings.version",
            options: versions.map { version in
                PlayerSettingsOption(
                    id: version.id,
                    title: version.title,
                    subtitle: version.subtitle,
                    isSelected: version.isSelected,
                    isDisabled: !version.isAvailable,
                    action: { onSelect(version.id) },
                )
            },
            closeStyle: .back,
            onClose: onClose,
        )
    }
}
