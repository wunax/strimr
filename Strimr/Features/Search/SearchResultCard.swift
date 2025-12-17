import Foundation
import SwiftUI

struct SearchResultCard: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    let media: MediaItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                MediaImageView(
                    viewModel: MediaImageViewModel(
                        context: plexApiContext,
                        artworkKind: .thumb,
                        media: media
                    )
                )
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
                .overlay(alignment: .topTrailing) {
                    WatchStatusBadge(media: media)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(media.primaryLabel)
                            .font(.headline)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        TypeBadge(type: media.type)
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let summary = media.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TypeBadge: View {
    let type: PlexItemType

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.15))
            )
            .foregroundStyle(color)
    }

    private var label: String {
        switch type {
        case .movie:
            return String(localized: "search.badge.movie")
        case .show:
            return String(localized: "search.badge.show")
        case .season:
            return String(localized: "search.badge.season")
        case .episode:
            return String(localized: "search.badge.episode")
        }
    }

    private var color: Color {
        switch type {
        case .movie:
            return .brandPrimary
        case .show:
            return .mint
        case .season:
            return .orange
        case .episode:
            return .purple
        }
    }
}

private extension SearchResultCard {
    var subtitle: String {
        switch media.type {
        case .movie:
            return media.year.map(String.init) ?? String(localized: "search.fallback.movie")
        case .show:
            return media.secondaryLabel ?? String(localized: "search.fallback.show")
        case .season:
            return media.secondaryLabel ?? media.title
        case .episode:
            return media.tertiaryLabel
                ?? media.secondaryLabel
                ?? media.parentTitle
                ?? String(localized: "search.fallback.episode")
        }
    }
}
