import Foundation
import SwiftUI

struct SearchResultCard: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    let media: MediaDisplayItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                MediaImageView(
                    viewModel: MediaImageViewModel(
                        context: plexApiContext,
                        artworkKind: .thumb,
                        media: media,
                    ),
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
                    .fill(Color.gray.opacity(0.08)),
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
                    .fill(color.opacity(0.15)),
            )
            .foregroundStyle(color)
    }

    private var label: String {
        switch type {
        case .movie:
            String(localized: "search.badge.movie")
        case .show:
            String(localized: "search.badge.show")
        case .season:
            String(localized: "search.badge.season")
        case .episode:
            String(localized: "search.badge.episode")
        case .collection:
            String(localized: "search.badge.collection")
        case .playlist:
            String(localized: "search.badge.playlist")
        case .unknown:
            String(localized: "search.badge.unknown")
        }
    }

    private var color: Color {
        switch type {
        case .movie:
            .brandPrimary
        case .show:
            .mint
        case .season:
            .orange
        case .episode:
            .purple
        case .collection:
            .teal
        case .playlist:
            .indigo
        case .unknown:
            .gray
        }
    }
}

private extension SearchResultCard {
    var subtitle: String {
        switch media.type {
        case .movie:
            media.playableItem?.year.map(String.init) ?? String(localized: "search.fallback.movie")
        case .show:
            media.secondaryLabel ?? String(localized: "search.fallback.show")
        case .season:
            media.secondaryLabel ?? media.title
        case .episode:
            media.tertiaryLabel
                ?? media.secondaryLabel
                ?? media.playableItem?.parentTitle
                ?? String(localized: "search.fallback.episode")
        case .collection:
            media.secondaryLabel ?? String(localized: "search.fallback.collection")
        case .playlist:
            media.secondaryLabel ?? String(localized: "search.fallback.playlist")
        case .unknown:
            media.title
        }
    }
}
