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
                .font(.title2.weight(.semibold).monospacedDigit())
            Text(playerTimestampText(feedback.target))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.72)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1),
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feedback.accessibilityText)
    }
}
