import SwiftUI

struct SeerrMediaSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: .init(title)))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.brandSecondary)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.brandPrimary)
                    .frame(width: 32, height: 4)
            }
            .padding(.horizontal, 2)

            content
        }
    }
}
