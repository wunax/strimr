import SwiftUI

struct PlayerIconButton: View {
    let systemName: String
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.18),
                            .white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 12)
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
                .font(.title.weight(.black))
                .foregroundStyle(.black)
                .frame(width: 72, height: 72)
                .background(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 14)
        }
        .accessibilityLabel(isPaused
            ? String(localized: "common.actions.play")
            : String(localized: "common.actions.pause")
        )
    }
}

struct SkipMarkerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color.white.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 12)
        }
        .accessibilityLabel(title)
    }
}
