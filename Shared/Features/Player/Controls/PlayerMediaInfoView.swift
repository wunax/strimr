import SwiftUI

enum PlayerMediaInfoLayout {
    /// Artwork beside every detail; fits short, wide surfaces such as the tvOS info tab.
    case wide
    /// Artwork beside the headline, with the synopsis below; fits sheets and popovers.
    case stacked
}

@MainActor
struct PlayerMediaInfoView: View {
    let media: MediaItem
    let services: MediaServices?
    var layout: PlayerMediaInfoLayout = .stacked
    var summaryLineLimit: Int?

    @Environment(SettingsManager.self) private var settingsManager

    private var isEpisode: Bool {
        media.type == .episode
    }

    var body: some View {
        switch layout {
        case .wide:
            HStack(alignment: .top, spacing: artworkSpacing) {
                artwork
                VStack(alignment: .leading, spacing: 14) {
                    headline
                    descriptiveDetails
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .stacked:
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: artworkSpacing) {
                    artwork
                    headline
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                descriptiveDetails
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEpisode, let seriesTitle = media.grandparentTitle {
                Text(seriesTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(media.title)
                .font(.title3.weight(.bold))
                .lineLimit(2)

            if let metadataText {
                Text(metadataText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !media.ratings.isEmpty {
                HStack(spacing: 16) {
                    ForEach(media.ratings.indices, id: \.self) { index in
                        MediaRatingLabel(rating: media.ratings[index], iconHeight: ratingIconHeight)
                    }
                }
                .font(.subheadline)
                .padding(.top, 2)
            }
        }
    }

    private var descriptiveDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isEpisode, let tagline = media.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary)
            }

            if media.shouldHideSpoilerSummary(at: settingsManager.interface.spoilerProtection) {
                Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let summary = media.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .lineLimit(summaryLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !media.genres.isEmpty {
                Text(media.genres.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let services {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    services: services,
                    artworkKind: isEpisode ? .art : .thumb,
                    media: .playable(media),
                ),
            )
            .frame(width: artworkSize.width, height: artworkSize.height)
            .mediaArtworkStyle(.compact, borderColor: .white.opacity(0.12))
            .accessibilityHidden(true)
        }
    }

    private var metadataText: String? {
        var items: [String] = []

        if let episodeLabel = media.tertiaryLabel {
            items.append(episodeLabel)
        }

        if let releaseDate = media.releaseDate {
            // Release dates are calendar days anchored to UTC midnight; formatting them in the local
            // time zone would shift them to the previous day west of Greenwich.
            let style = Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt)
            items.append(String(localized: "player.info.releaseDate \(releaseDate.formatted(style))"))
        } else if let year = media.year {
            items.append(String(year))
        }

        if let duration = media.duration, duration > 0 {
            items.append(duration.mediaDurationText())
        }

        if let contentRating = media.contentRating, !contentRating.isEmpty {
            items.append(contentRating)
        }

        return items.isEmpty ? nil : items.joined(separator: " · ")
    }

    private var artworkSize: CGSize {
        let width: CGFloat = if isEpisode {
            #if os(tvOS)
                420
            #elseif os(macOS)
                180
            #else
                160
            #endif
        } else {
            #if os(tvOS)
                200
            #elseif os(macOS)
                100
            #else
                92
            #endif
        }
        return CGSize(width: width, height: isEpisode ? width * 9 / 16 : width * 3 / 2)
    }

    private var artworkSpacing: CGFloat {
        #if os(tvOS)
            40
        #else
            16
        #endif
    }

    private var ratingIconHeight: CGFloat {
        #if os(tvOS)
            24
        #else
            16
        #endif
    }
}
