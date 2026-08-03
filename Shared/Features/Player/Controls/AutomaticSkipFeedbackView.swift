import SwiftUI

struct AutomaticSkipFeedbackView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "forward.fill")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.72)),
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1),
            )
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 5)
            .accessibilityElement(children: .combine)
    }
}
