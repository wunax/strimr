import SwiftUI

struct AutomaticSkipFeedbackView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "forward.fill")
            .font(.facts.weight(.semibold))
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .videoOverlayGlass()
            .accessibilityElement(children: .combine)
    }
}
