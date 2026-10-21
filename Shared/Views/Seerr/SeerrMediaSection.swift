import SwiftUI

struct SeerrMediaSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: .init(title)))
                .font(.sectionTitle)
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 2)

            content
        }
    }
}
