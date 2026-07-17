import SwiftUI

struct MediaHubSection<Content: View>: View {
    let title: String
    let onViewAll: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        onViewAll: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.onViewAll = onViewAll
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                titleView
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.brandPrimary)
                    .frame(width: 32, height: 4)
            }
            .padding(.horizontal, 2)

            content
        }
    }

    @ViewBuilder
    private var titleView: some View {
        #if !os(tvOS)
            if let onViewAll {
                Button(action: onViewAll) {
                    HStack(spacing: 4) {
                        titleText
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("hub.viewAll"))
            } else {
                titleText
            }
        #else
            titleText
        #endif
    }

    private var titleText: some View {
        Text(title)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(.brandSecondary)
    }
}
