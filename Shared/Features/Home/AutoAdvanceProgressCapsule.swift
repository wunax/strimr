import SwiftUI

/// The current page's dot in a hero page indicator, filling up until the next auto-advance.
struct AutoAdvanceProgressCapsule: View {
    /// When the current page's auto-advance started; nil while it is paused or off, which shows the dot full.
    let startedAt: Date?
    let interval: Duration

    var body: some View {
        TimelineView(.animation(paused: startedAt == nil)) { context in
            Capsule()
                .fill(.textTertiary)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.progressFill)
                            .frame(width: max(proxy.size.height, proxy.size.width * progress(at: context.date)))
                    }
                }
                .clipShape(Capsule())
        }
    }

    private func progress(at date: Date) -> CGFloat {
        guard let startedAt else { return 1 }
        let seconds = Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18
        return min(max(date.timeIntervalSince(startedAt) / seconds, 0), 1)
    }
}
