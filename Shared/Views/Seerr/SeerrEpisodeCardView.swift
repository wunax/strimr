import SwiftUI

/// Episode row of a Seerr series, laid out like the library one but without playback.
struct SeerrEpisodeCardView: View {
    let episode: SeerrEpisode
    let imageURL: URL?
    let label: String?
    let airDateText: String?
    #if !os(macOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @State private var rowWidth: CGFloat = 0

        private var isRegularWidth: Bool {
            #if os(tvOS)
                false
            #else
                horizontalSizeClass == .regular
            #endif
        }
    #endif

    var body: some View {
        #if os(macOS)
            HStack(spacing: 16) {
                SeerrEpisodeArtworkView(imageURL: imageURL, width: 200)
                caption
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                .surfaceSubtle,
                in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous),
            )
        #else
            Group {
                if isRegularWidth {
                    HStack(alignment: .top, spacing: 16) {
                        SeerrEpisodeArtworkView(imageURL: imageURL, width: rowWidth / 3)
                        caption
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        GeometryReader { proxy in
                            SeerrEpisodeArtworkView(imageURL: imageURL, width: proxy.size.width)
                        }
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)

                        caption
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .padding(.vertical, 12)
        #endif
    }

    private var caption: some View {
        EpisodeCaption(
            eyebrow: [label, airDateText].compactMap(\.self).joined(separator: " · "),
            title: title,
        ) {
            if let summary = episode.overview, !summary.isEmpty {
                Text(summary)
            }
        }
    }

    private var title: String {
        if let name = episode.name, !name.isEmpty {
            return name
        }
        return episode.episodeNumber.map { String(localized: "media.detail.episodeNumber \($0)") } ?? ""
    }
}

private struct SeerrEpisodeArtworkView: View {
    let imageURL: URL?
    let width: CGFloat

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Color.surfaceSubtle
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .mediaArtworkStyle(.compact, borderColor: .white.opacity(0.05))
    }
}
