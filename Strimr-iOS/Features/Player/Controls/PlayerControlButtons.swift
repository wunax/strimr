import SwiftUI

struct SkipMarkerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
            }
        }
        .actionButtonStyle(.primary)
        .accessibilityLabel(title)
    }
}

struct PlayerSettingsButton: View {
    var showsIndicator = false
    let action: () -> Void

    var body: some View {
        PlayerIconButton(
            systemName: "gearshape",
            accessibilityLabel: String(localized: "settings.title"),
            size: .small,
            action: action,
        )
        .overlay(alignment: .topTrailing) {
            if showsIndicator {
                PlaybackOffsetIndicator()
                    .offset(x: 2, y: -2)
            }
        }
    }
}

struct PlayerPictureInPictureButton: View {
    let action: () -> Void

    var body: some View {
        PlayerIconButton(
            systemName: "pip.enter",
            accessibilityLabel: String(localized: "player.controls.pictureInPicture"),
            size: .small,
            action: action,
        )
    }
}

struct RotationLockButton: View {
    var isLocked: Bool
    let action: () -> Void

    var body: some View {
        PlayerIconButton(
            systemName: isLocked ? "lock.fill" : "lock.open",
            accessibilityLabel: isLocked
                ? String(localized: "player.controls.rotation.unlock")
                : String(localized: "player.controls.rotation.lock"),
            size: .small,
            isSelected: isLocked,
            action: action,
        )
    }
}
