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
    let action: () -> Void

    var body: some View {
        PlayerIconButton(
            systemName: "gearshape",
            accessibilityLabel: String(localized: "settings.title"),
            size: .small,
            action: action,
        )
    }
}

struct PlayerTracksMenuButton: View {
    let model: PlayerTracksMenuModel
    let actions: PlayerTracksMenuActions

    var body: some View {
        PlayerTracksMenu(model: model, actions: actions) {
            Image(systemName: "text.bubble")
                .font(PlayerIconButton.Size.small.font)
        }
        .equatable()
        .buttonStyle(.playerControl(diameter: PlayerIconButton.Size.small.diameter))
        .accessibilityLabel(Text("player.tracks.title"))
        .overlay(alignment: .topTrailing) {
            if model.showsIndicator {
                PlaybackOffsetIndicator()
                    .offset(x: 2, y: -2)
                    .allowsHitTesting(false)
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

struct ControlsLockButton: View {
    var isLocked: Bool
    let action: () -> Void

    var body: some View {
        PlayerIconButton(
            systemName: isLocked ? "lock.fill" : "lock.open",
            accessibilityLabel: isLocked
                ? String(localized: "player.controls.touchLock.unlock")
                : String(localized: "player.controls.touchLock.lock"),
            size: .small,
            isSelected: isLocked,
            action: action,
        )
    }
}
