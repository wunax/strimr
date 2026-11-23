import SwiftUI

/// Round icon of a secondary detail action, as tall as the play button so it stays the lead; the title goes in the
/// tooltip.
struct DetailCircleActionLabel: View {
    static let size = LayoutMetrics.actionButtonHeight

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPointerOver = false

    let systemImage: String
    let isActive: Bool
    let isLoading: Bool
    /// Replaces the loading spinner with a ring and percentage when the work reports how far it is.
    var progress: Double?
    /// Set by a menu, whose label does not receive pointer events itself.
    var isHovered: Bool?

    var body: some View {
        ZStack {
            Circle()
                .fill(isLifted ? Color.white.opacity(0.22) : Color.surfaceRaised)
            if isLoading, let progress {
                DownloadProgressRing(progress: progress, lineWidth: 2.5)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isActive || isLifted ? .textPrimary : .textSecondary)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Circle())
        .shadow(color: .black.opacity(isLifted ? 0.35 : 0), radius: 12, y: 4)
        .animation(Motion.focus, value: isLifted)
        .scaleEffect(isLifted && !reduceMotion ? 1.06 : 1)
        .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isLifted)
        .onHover { isPointerOver = $0 }
        .accessibilityValue(progressValue)
    }

    private var progressValue: Text {
        guard isLoading, let progress else { return Text(verbatim: "") }
        return Text(progress, format: .percent.precision(.fractionLength(0)))
    }

    private var isLifted: Bool {
        (isHovered ?? isPointerOver) && isEnabled
    }
}
