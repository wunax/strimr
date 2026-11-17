import SwiftUI

/// Fills a skip button with the brand color from the leading edge while its automatic skip counts down.
struct SkipCountdownFill: View {
    let countdown: AutomaticMarkerSkip.Countdown?

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.brandPrimary)
                .frame(width: proxy.size.width * (countdown?.progress ?? 0))
        }
        .opacity(countdown == nil ? 0 : 1)
        .animation(.linear(duration: 0.25), value: countdown?.progress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Multiply keeps the dark label readable where the fill passes under it.
    func skipCountdownOverlay(_ countdown: AutomaticMarkerSkip.Countdown?) -> some View {
        overlay {
            SkipCountdownFill(countdown: countdown)
                .blendMode(.multiply)
                .clipShape(Capsule(style: .continuous))
        }
    }
}

extension AutomaticMarkerSkip.Countdown {
    var accessibilityValue: String {
        String(localized: "player.skip.countdown.accessibilityValue \(remainingSeconds)")
    }
}
