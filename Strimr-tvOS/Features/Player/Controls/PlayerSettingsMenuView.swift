import SwiftUI

struct PlayerSettingsMenuView: View {
    var qualityTitle: String?
    var versionTitle: String?
    let sleepTimer: SleepTimer
    var mediaKind: MediaKind?
    var initialOptionID: String?
    var onShowQuality: () -> Void
    var onShowVersions: () -> Void
    var onShowSleepTimer: () -> Void
    var onClose: () -> Void

    var body: some View {
        PlayerSettingsOptionsView(
            title: "settings.title",
            options: options,
            initialOptionID: initialOptionID,
            onClose: onClose,
        )
    }

    private var options: [PlayerSettingsOption] {
        var options: [PlayerSettingsOption] = []

        if let qualityTitle {
            options.append(PlayerSettingsOption(
                id: "quality",
                title: String(localized: "player.settings.quality"),
                subtitle: qualityTitle,
                systemImage: "slider.horizontal.3",
                opensSubmenu: true,
                action: onShowQuality,
            ))
        }

        if let versionTitle {
            options.append(PlayerSettingsOption(
                id: "version",
                title: String(localized: "player.settings.version"),
                subtitle: versionTitle,
                systemImage: "film.stack",
                opensSubmenu: true,
                action: onShowVersions,
            ))
        }

        options.append(PlayerSettingsOption(
            id: "sleepTimer",
            title: String(localized: "player.sleepTimer.title"),
            subtitle: sleepTimerSubtitle,
            highlightsSubtitle: sleepTimer.isActive,
            systemImage: sleepTimer.isActive ? "moon.zzz.fill" : "moon.zzz",
            opensSubmenu: true,
            action: onShowSleepTimer,
        ))

        return options
    }

    private var sleepTimerSubtitle: String {
        if let deadline = sleepTimer.deadline {
            return String(localized: "player.sleepTimer.endsAt \(deadline.formatted(date: .omitted, time: .shortened))")
        }
        return sleepTimer.mode?.title(for: mediaKind) ?? String(localized: "player.sleepTimer.off")
    }
}
