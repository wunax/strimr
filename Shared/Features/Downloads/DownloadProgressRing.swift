import SwiftUI

struct DownloadProgressRing: View {
    enum Style {
        case transfer
        /// Dotted and dimmer, so the server's conversion reads apart from the file transfer that follows it.
        case serverPreparation
    }

    struct Value: Equatable {
        var progress: Double
        var style: Style
    }

    let value: Value
    let lineWidth: CGFloat

    private var progress: Double {
        value.progress
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.progressTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(fillColor, style: strokeStyle)
                .rotationEffect(.degrees(-90))
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.badge.monospacedDigit())
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, lineWidth + 2)
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        switch value.style {
        case .transfer: .progressFill
        case .serverPreparation: .progressBuffered
        }
    }

    private var strokeStyle: StrokeStyle {
        switch value.style {
        case .transfer:
            StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        case .serverPreparation:
            StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [0.1, lineWidth * 2])
        }
    }
}
