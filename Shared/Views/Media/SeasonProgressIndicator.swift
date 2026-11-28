import SwiftUI

/// Ring of the episodes watched in a season, turned into a checkmark once all are watched. It takes the chip's
/// foreground so it stays readable on a selected chip.
struct SeasonProgressIndicator: View {
    let progress: EpisodeProgress

    #if os(tvOS)
        @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 20
        private let lineWidth: CGFloat = 3
    #else
        @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 12
        private let lineWidth: CGFloat = 2
    #endif

    var body: some View {
        Group {
            if progress.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Circle()
                        .stroke(.foreground.opacity(0.3), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: progress.fraction)
                        .stroke(.foreground, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(lineWidth / 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension View {
    @ViewBuilder
    func seasonProgressAccessibility(_ progress: EpisodeProgress?) -> some View {
        if let progress {
            accessibilityValue(String(localized: "media.detail.seasonProgress \(progress.watched) \(progress.total)"))
        } else {
            self
        }
    }
}
