import SwiftUI

/// Round glass button of the player controls. Filled white for the play button, like the primary action button, and
/// for a toggle that is on, like a selected chip.
struct PlayerControlButtonStyle: ButtonStyle {
    var diameter: CGFloat
    var isFilled = false

    func makeBody(configuration: Configuration) -> some View {
        PlayerControlButton(configuration: configuration, diameter: diameter, isFilled: isFilled)
    }

    private struct PlayerControlButton: View {
        @Environment(\.isEnabled) private var isEnabled

        let configuration: Configuration
        let diameter: CGFloat
        let isFilled: Bool

        var body: some View {
            Group {
                if isFilled {
                    label.background(.white, in: Circle())
                } else {
                    label.videoOverlayGlass(in: Circle())
                }
            }
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
        }

        private var label: some View {
            configuration.label
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
        }

        private var foreground: Color {
            if !isEnabled {
                return .textTertiary
            }
            return isFilled ? .black : .textPrimary
        }
    }
}

extension ButtonStyle where Self == PlayerControlButtonStyle {
    static func playerControl(diameter: CGFloat, isFilled: Bool = false) -> PlayerControlButtonStyle {
        PlayerControlButtonStyle(diameter: diameter, isFilled: isFilled)
    }
}

struct PlayerIconButton: View {
    enum Size {
        /// Header and corner buttons, such as settings or rotation lock.
        case small
        /// Seek buttons beside play.
        case regular
    }

    let systemName: String
    var accessibilityLabel: String?
    var size: Size = .regular
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
        }
        .buttonStyle(.playerControl(diameter: diameter, isFilled: isSelected))
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }

    private var diameter: CGFloat {
        switch size {
        case .small:
            44
        case .regular:
            58
        }
    }

    private var font: Font {
        switch size {
        case .small:
            .headline.weight(.semibold)
        case .regular:
            .title3.weight(.bold)
        }
    }
}

struct PlayPauseButton: View {
    var isPaused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.title.weight(.black))
        }
        .buttonStyle(.playerControl(diameter: 72, isFilled: true))
        .accessibilityLabel(isPaused
            ? String(localized: "common.actions.play")
            : String(localized: "common.actions.pause"))
    }
}

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
