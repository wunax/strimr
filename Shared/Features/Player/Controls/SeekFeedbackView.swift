import SwiftUI

struct SeekFeedback: Equatable {
    let forward: Bool
    let start: Double
    let target: Double

    /// Keeps the running total of `previous` when seeking the same way again; a direction change starts over.
    static func next(after previous: SeekFeedback?, forward: Bool, origin: Double, target: Double) -> SeekFeedback {
        let start = previous.flatMap { $0.forward == forward ? $0.start : nil } ?? origin
        return SeekFeedback(forward: forward, start: start, target: target)
    }

    var seconds: Int {
        Int(abs(target - start).rounded())
    }

    var deltaText: String {
        let duration = Duration.seconds(seconds).formatted(.units(
            allowed: [.hours, .minutes, .seconds],
            width: .narrow,
        ))
        return "\(forward ? "+" : "−")\(duration)"
    }

    var accessibilityText: String {
        if forward {
            return String(localized: "player.controls.skipForwardSeconds \(seconds)")
        }
        return String(localized: "player.controls.rewindSeconds \(seconds)")
    }

    var systemImage: String {
        forward ? "goforward" : "gobackward"
    }
}

struct SeekFeedbackView: View {
    let feedback: SeekFeedback

    var body: some View {
        VStack(spacing: 4) {
            Label(feedback.deltaText, systemImage: feedback.systemImage)
                .font(.tileTitle.monospacedDigit())
            Text(playerTimestampText(feedback.target))
                .font(.facts.monospacedDigit())
                .foregroundStyle(.textSecondary)
        }
        .foregroundStyle(.textPrimary)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .videoOverlayGlass(
            in: RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous),
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feedback.accessibilityText)
    }
}
