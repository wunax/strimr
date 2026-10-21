import SwiftUI

/// Facts separated by middle dots, followed by the content rating and technical badges.
struct MediaFactsLine: View {
    let facts: MediaFacts
    var badges: [String] = []

    var body: some View {
        if !facts.isEmpty || !badges.isEmpty {
            HStack(spacing: spacing) {
                if !facts.tokens.isEmpty {
                    Text(facts.tokens.joined(separator: " · "))
                        .font(.facts)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }
                if let contentRating = facts.contentRating {
                    ContentRatingBadge(text: contentRating)
                }
                ForEach(badges, id: \.self) { badge in
                    TechBadge(text: badge)
                }
            }
        }
    }

    private var spacing: CGFloat {
        #if os(tvOS)
            14
        #else
            8
        #endif
    }
}

/// Outlined capsule for a content rating such as `PG-13`.
struct ContentRatingBadge: View {
    let text: String

    var body: some View {
        OutlinedBadge(text: text)
            .accessibilityLabel(Text("media.detail.contentRating \(text)"))
    }
}

/// Outlined capsule for a technical trait such as `4K`, `DV` or `5.1`.
struct TechBadge: View {
    let text: String

    var body: some View {
        OutlinedBadge(text: text)
    }
}

private struct OutlinedBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.badge)
            .foregroundStyle(.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.strokeSubtle, lineWidth: 1)
            }
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            10
        #else
            6
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            3
        #else
            2
        #endif
    }
}
