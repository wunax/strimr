import Foundation
import SwiftUI

struct SearchResultCard: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(ServerRegistry.self) private var registry
    let result: MergedSearchResult
    let onTap: () -> Void

    private var media: MediaDisplayItem {
        result.media
    }

    /// Hierarchical styles rather than the fixed text tokens: the focused tvOS button turns white and they invert.
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ItemArtworkView(services: registry.services(for: media.server), kind: .thumb, media: media)
                    .frame(width: 100, height: 150)
                    .mediaArtworkStyle()
                    .overlay(alignment: .topTrailing) {
                        WatchStatusBadge(media: media)
                    }
                    .downloadStatusOverlay(media)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(media.primaryLabel)
                            .font(.rowTitle)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        MediaTypeBadge(type: media.type)
                    }

                    Text(subtitle)
                        .font(.facts)
                        .foregroundStyle(.secondary)

                    if result.sources.count > 1 {
                        Label(result.serverNames.joined(separator: ", "), systemImage: "server.rack")
                            .font(.cardMetadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if media.playableItem?.shouldHideSpoilerSummary(
                        at: settingsManager.interface.spoilerProtection,
                    ) == true {
                        Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
                            .font(.facts)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else if let summary = media.summary, !summary.isEmpty {
                        Text(summary)
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
        .offlineAvailability(of: media)
    }
}

/// Discreet notice listing the servers that did not answer; their results are simply missing.
struct SearchUnavailableServersNote: View {
    let names: [String]

    var body: some View {
        if !names.isEmpty {
            Label(
                String(localized: "search.serverUnavailable \(names.formatted(.list(type: .and)))"),
                systemImage: "exclamationmark.icloud",
            )
            .font(.facts)
            .foregroundStyle(.textTertiary)
        }
    }
}

struct SearchServerSelectionView: View {
    let result: MergedSearchResult
    let onSelect: (SearchResultSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ServerRegistry.self) private var registry
    @Environment(LibraryStore.self) private var libraryStore
    @State private var libraryIDs: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List(result.sourcesByQuality) { source in
                Button {
                    dismiss()
                    onSelect(source)
                } label: {
                    row(for: source)
                }
            }
            // Buttons in a list draw their label in the accent color.
            .tint(Color.primary)
            .navigationTitle("search.serverSelection.title")
        }
        .presentationDetents([.medium, .large])
        .task { await loadLibraryIDs() }
    }

    private func row(for source: SearchResultSource) -> some View {
        HStack(spacing: Self.spacing) {
            Image(systemName: "server.rack")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .background(Circle().fill(.quaternary))

            VStack(alignment: .leading, spacing: 4) {
                Text(source.serverName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                if let library = libraryTitle(for: source) {
                    HStack(spacing: 6) {
                        Image(systemName: "books.vertical")
                        Text(library)
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                }
            }

            Spacer(minLength: Self.spacing)

            if let resolution = source.media.playableItem?.playbackResolutionLabel {
                Text(resolution)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().strokeBorder(Color.primary, lineWidth: 1.5))
            }
        }
        .padding(.vertical, 4)
    }

    #if os(tvOS)
        private static let iconSize: CGFloat = 64
        private static let spacing: CGFloat = 24
    #else
        private static let iconSize: CGFloat = 36
        private static let spacing: CGFloat = 12
    #endif

    private func libraryTitle(for source: SearchResultSource) -> String? {
        if let title = source.media.playableItem?.librarySectionTitle {
            return title
        }
        guard let libraryID = source.media.playableItem?.librarySectionID ?? libraryIDs[source.id] else { return nil }
        return libraryStore.library(LibraryIdentity(server: source.server, libraryID: libraryID))?.title
    }

    /// Jellyfin search results do not carry their library; it takes one request per copy.
    private func loadLibraryIDs() async {
        await withTaskGroup(of: (String, String?).self) { group in
            for source in result.sources {
                guard let item = source.media.playableItem, item.librarySectionID == nil,
                      let detail = registry.services(for: source.server)?.detail
                else { continue }
                group.addTask { (source.id, try? await detail.libraryID(for: item)) }
            }
            for await (id, libraryID) in group {
                libraryIDs[id] = libraryID
            }
        }
    }
}

/// Colored capsule naming the kind of a search result.
struct MediaTypeBadge: View {
    let type: MediaKind

    var body: some View {
        Text(label)
            .font(.badge)
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
        case .series:
            String(localized: "search.badge.show")
        case .season:
            String(localized: "search.badge.season")
        case .episode:
            String(localized: "search.badge.episode")
        case .clip:
            String(localized: "search.badge.clip")
        case .collection:
            String(localized: "search.badge.collection")
        case .playlist:
            String(localized: "search.badge.playlist")
        case .folder, .unknown:
            String(localized: "search.badge.unknown")
        }
    }

    private var color: Color {
        switch type {
        case .movie:
            .gray
        case .series:
            .mint
        case .season:
            .orange
        case .episode:
            .purple
        case .clip:
            .gray
        case .collection:
            .teal
        case .playlist:
            .indigo
        case .folder, .unknown:
            .gray
        }
    }
}

private extension SearchResultCard {
    var subtitle: String {
        switch media.type {
        case .movie:
            media.secondaryLabel ?? String(localized: "search.fallback.movie")
        case .series:
            media.secondaryLabel ?? String(localized: "search.fallback.show")
        case .season:
            media.cardSecondaryLabel(remainingTime: nil) ?? media.title
        case .episode:
            media.cardTertiaryLabel(remainingTime: nil)
                ?? media.secondaryLabel
                ?? media.playableItem?.parentTitle
                ?? String(localized: "search.fallback.episode")
        case .clip:
            media.title
        case .collection:
            media.secondaryLabel ?? String(localized: "search.fallback.collection")
        case .playlist:
            media.secondaryLabel ?? String(localized: "search.fallback.playlist")
        case .folder, .unknown:
            media.title
        }
    }
}
