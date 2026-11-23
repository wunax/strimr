import SwiftUI

/// Ring filled to the download progress, with the percentage inside; drawn in a detail page's round download button.
struct DownloadProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.progressTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.progressFill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, lineWidth + 2)
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}
