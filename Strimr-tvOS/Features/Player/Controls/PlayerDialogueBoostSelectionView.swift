import SwiftUI

struct PlayerDialogueBoostSelectionView: View {
    var selectedBoost: DialogueBoost
    var onSelect: (DialogueBoost) -> Void

    var body: some View {
        PlayerSettingsOptionsView(
            title: "settings.playback.dialogueBoost",
            options: DialogueBoost.allCases.map { boost in
                PlayerSettingsOption(
                    id: boost.rawValue,
                    title: boost.title,
                    isSelected: boost == selectedBoost,
                    action: { onSelect(boost) },
                )
            },
            parentTitle: "player.settings.audio",
        )
    }
}
