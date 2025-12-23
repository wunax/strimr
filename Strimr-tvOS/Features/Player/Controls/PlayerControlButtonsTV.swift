import SwiftUI

struct PlayerIconButton: View {
    let systemName: String
    var accessibilityLabel: String?
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(isFocused ? .black : .white)
                .frame(width: 88, height: 88)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(isFocused ? Color.white : Color.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(isFocused ? Color.white.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isFocused ? 0.35 : 0.2), radius: isFocused ? 18 : 8, x: 0, y: isFocused ? 12 : 6)
                .scaleEffect(isFocused ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($isFocused)
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

struct PlayPauseButton: View {
    var isPaused: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(.black)
                .frame(width: 108, height: 108)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(isFocused ? Color.white : Color.white.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(isFocused ? 0.6 : 0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isFocused ? 0.4 : 0.25), radius: isFocused ? 22 : 12, x: 0, y: isFocused ? 14 : 8)
                .scaleEffect(isFocused ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($isFocused)
        .accessibilityLabel(isPaused
            ? String(localized: "common.actions.play")
            : String(localized: "common.actions.pause")
        )
    }
}

struct SkipMarkerButton: View {
    let title: String
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
            }
            .foregroundStyle(isFocused ? .black : .white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isFocused ? Color.white.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isFocused ? 0.3 : 0.2), radius: isFocused ? 16 : 8, x: 0, y: isFocused ? 10 : 6)
            .scaleEffect(isFocused ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($isFocused)
        .accessibilityLabel(title)
    }
}

struct PlayerSettingButton: View {
    var systemImage: String
    var action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isFocused ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [
                            .white.opacity(isFocused ? 1.0 : 0.18),
                            .white.opacity(isFocused ? 0.9 : 0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule(style: .continuous)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isFocused ? Color.white.opacity(0.6) : Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isFocused ? 0.3 : 0.2), radius: isFocused ? 12 : 6, x: 0, y: isFocused ? 8 : 4)
                .scaleEffect(isFocused ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($isFocused)
    }
}
