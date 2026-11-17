import SwiftUI

struct PlayerIconButton: View {
    let systemName: String
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.foreground)
                .frame(width: 72, height: 72)
        }
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

struct PlayPauseButton: View {
    var isPaused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(.foreground)
                .frame(width: 108, height: 108)
        }
        .accessibilityLabel(
            isPaused
                ? String(localized: "common.actions.play")
                : String(localized: "common.actions.pause"),
        )
    }
}

struct SkipMarkerButton: View {
    let title: String
    var countdown: AutomaticMarkerSkip.Countdown?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
            }
            .foregroundStyle(.foreground)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            // Inside the label so the fill lifts with the focused platter.
            .background {
                SkipCountdownFill(countdown: countdown)
                    .clipShape(Capsule(style: .continuous))
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(countdown?.accessibilityValue ?? "")
    }
}

struct PlayerSettingButton: View {
    var systemImage: String
    var accessibilityLabel: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(.foreground)
                .frame(width: 52, height: 52)
        }
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}
