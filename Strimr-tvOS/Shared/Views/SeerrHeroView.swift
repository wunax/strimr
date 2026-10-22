import SwiftUI
import UIKit

struct SeerrHeroBackgroundView: View {
    let media: SeerrMedia

    var body: some View {
        HeroBackdropView(key: media.id, load: loadBackdrop)
    }

    private var heroImageURL: URL? {
        TMDBImageService.backdropURL(path: media.backdropPath, width: 1400)
            ?? TMDBImageService.posterURL(path: media.posterPath, width: 780)
    }

    private var gradientImageURL: URL? {
        TMDBImageService.backdropURL(path: media.backdropPath, width: 300)
            ?? TMDBImageService.posterURL(path: media.posterPath, width: 300)
    }

    private func loadBackdrop() async -> HeroBackdrop {
        let resource = heroImageURL.map(ArtworkResource.url)
        if let resource {
            await ArtworkResourceView.preload(resource)
        }

        guard let gradientImageURL,
              let colors = try? await ImageCornerColorSampler.colors(from: .url(gradientImageURL)),
              colors.count == 4
        else {
            return HeroBackdrop(resource: resource)
        }
        return HeroBackdrop(resource: resource, colors: colors)
    }
}

struct SeerrHeroContentView: View {
    let media: SeerrMedia
    /// Scores loaded by the detail page; elsewhere only the TMDB vote that comes with the item is shown.
    var ratings: SeerrMediaRatings?
    var isDownloading = false

    var body: some View {
        HeroContentTransitionView(item: media) { media in
            SeerrHeroDetailsView(
                media: media,
                ratings: MediaRating.ratings(from: ratings, voteAverage: media.voteAverage),
                isDownloading: isDownloading || media.mediaInfo?.isDownloading == true,
            )
        }
    }
}

/// Same layout as the library hero: a title in the room of a logo, then facts, summary and availability.
private struct SeerrHeroDetailsView: View {
    let media: SeerrMedia
    let ratings: [MediaRating]
    let isDownloading: Bool
    private let summaryLineLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Fixed height so a two-line title never moves what follows during hero transitions.
            Text(media.displayTitle)
                .font(.heroTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(
                    maxWidth: .infinity,
                    minHeight: LayoutMetrics.heroLogoMaxSize.height,
                    maxHeight: LayoutMetrics.heroLogoMaxSize.height,
                    alignment: .bottomLeading,
                )
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 24) {
                MediaFactsLine(facts: MediaFactsFormatter.facts(for: media))
                ratingsLine
                if let status = media.mediaInfo?.status {
                    SeerrAvailabilityBadgeView(status: status, showsLabel: true, isDownloading: isDownloading)
                }
            }

            if let overview = media.overview, !overview.isEmpty {
                Text(overview)
                    .font(.bodyText)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(summaryLineLimit)
                    .frame(minHeight: summaryLineHeight * CGFloat(summaryLineLimit), alignment: .top)
            }
        }
    }

    private var summaryLineHeight: CGFloat {
        UIFont.systemFont(ofSize: 26).lineHeight
    }

    @ViewBuilder
    private var ratingsLine: some View {
        if !ratings.isEmpty {
            HStack(spacing: 16) {
                ForEach(Array(ratings.enumerated()), id: \.offset) { _, rating in
                    MediaRatingLabel(rating: rating)
                }
            }
            .font(.facts)
            .foregroundStyle(.textSecondary)
        }
    }
}
