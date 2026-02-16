import SwiftUI

struct SeerrEpisodeCardView: View {
    let episode: SeerrEpisode
    let imageURL: URL?
    let label: String?
    let airDateText: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        #if os(tvOS)
            false
        #else
            horizontalSizeClass == .regular
        #endif
    }

    private var regularImageWidth: CGFloat {
        #if os(visionOS)
        400
        #else
        UIScreen.main.bounds.width / 3
        #endif
    }

    var body: some View {
        Group {
            if isRegularWidth {
                HStack(alignment: .top, spacing: 16) {
                    SeerrEpisodeArtworkView(
                        imageURL: imageURL,
                        width: regularImageWidth,
                    )

                    detailStack
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { proxy in
                        SeerrEpisodeArtworkView(
                            imageURL: imageURL,
                            width: proxy.size.width,
                        )
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)

                    detailStack
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private var detailStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                if let label {
                    Text(label)
                        .font(labelFont)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let airDateText {
                    Text(airDateText)
                        .font(labelFont)
                        .foregroundStyle(.secondary)
                }
            }

            if !episodeTitle.isEmpty {
                Text(episodeTitle)
                    .font(titleFont)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            if let summary = episode.overview, !summary.isEmpty {
                Text(summary)
                    .font(summaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private var labelFont: Font {
        #if os(tvOS)
            .caption2
        #else
            .callout
        #endif
    }

    private var titleFont: Font {
        #if os(tvOS)
            .subheadline
        #else
            .title3
        #endif
    }

    private var summaryFont: Font {
        #if os(tvOS)
            .caption
        #else
            .callout
        #endif
    }

    private var episodeTitle: String {
        if let name = episode.name, !name.isEmpty {
            return name
        }
        if let episodeNumber = episode.episodeNumber {
            return String(localized: "media.detail.episodeNumber \(episodeNumber)")
        }
        return ""
    }
}

private struct SeerrEpisodeArtworkView: View {
    let imageURL: URL?
    let width: CGFloat
    private let aspectRatio: CGFloat = 16 / 9

    var height: CGFloat {
        width / aspectRatio
    }

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                Color.gray.opacity(0.15)
            case .failure:
                Color.gray.opacity(0.15)
            @unknown default:
                Color.gray.opacity(0.15)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.05))
        }
    }
}
