import SwiftUI

/// Seerr search result, laid out like a library search result.
struct SeerrSearchCard: View {
    let media: SeerrMedia
    let onTap: () -> Void

    /// Hierarchical styles rather than the fixed text tokens: the focused tvOS button turns white and they invert.
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                SeerrMediaArtworkView(media: media, width: 100, height: 150)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(media.displayTitle)
                            .font(.rowTitle)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        if let kind {
                            MediaTypeBadge(type: kind)
                        }
                    }

                    if let year = media.year {
                        Text(String(year))
                            .font(.facts)
                            .foregroundStyle(.secondary)
                    }

                    if let overview = media.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.facts)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                    .fill(.surfaceSubtle),
            )
        }
        .buttonStyle(.plain)
    }

    private var kind: MediaKind? {
        switch media.mediaType {
        case .movie:
            .movie
        case .tv:
            .series
        case .person, nil:
            nil
        }
    }
}
