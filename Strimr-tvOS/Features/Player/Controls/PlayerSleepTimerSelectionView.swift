import SwiftUI

struct PlayerSleepTimerSelectionView: View {
    let sleepTimer: SleepTimer
    var modes: [SleepTimerMode]
    var mediaKind: MediaKind?
    var isAvailable: Bool
    var onSelect: (SleepTimerMode?) -> Void
    var onClose: () -> Void

    var body: some View {
        PlayerSettingsOptionsView(
            title: "player.sleepTimer.title",
            options: options,
            closeStyle: .back,
            onClose: onClose,
        )
    }

    private var options: [PlayerSettingsOption] {
        var options = [
            PlayerSettingsOption(
                id: "off",
                title: String(localized: "player.sleepTimer.off"),
                isSelected: sleepTimer.mode == nil,
                action: { onSelect(nil) },
            ),
        ]

        if let deadline = sleepTimer.deadline {
            options.append(PlayerSettingsOption(
                id: "extend",
                title: String(localized: "player.sleepTimer.extend \(SleepTimer.extensionMinutes)"),
                subtitle: endsAtText(deadline),
                highlightsSubtitle: true,
                systemImage: "plus",
                action: { sleepTimer.extend() },
            ))
        }

        for (index, mode) in modes.enumerated() {
            options.append(PlayerSettingsOption(
                id: "\(mode)",
                title: mode.title(for: mediaKind),
                isSelected: sleepTimer.mode == mode,
                isDisabled: !isAvailable,
                sectionTitle: index == 0 && !isAvailable
                    ? String(localized: "player.sleepTimer.unavailableSharePlay")
                    : nil,
                action: { onSelect(mode) },
            ))
        }

        return options
    }

    private func endsAtText(_ deadline: Date) -> String {
        String(localized: "player.sleepTimer.endsAt \(deadline.formatted(date: .omitted, time: .shortened))")
    }
}
