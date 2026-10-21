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

    var body: some View {
        HeroContentTransitionView(item: media) { media in
            SeerrHeroDetailsView(media: media)
        }
    }
}

private struct SeerrHeroDetailsView: View {
    let media: SeerrMedia
    private let summaryLineLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayTitle)
                .font(.title2.bold())
                .lineLimit(2)

            if let tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.headline)
                    .foregroundStyle(.brandSecondary)
            }

            metadataLine
            genresLine

            if let overview, !overview.isEmpty {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.brandSecondary)
                    .lineLimit(summaryLineLimit)
                    .frame(minHeight: summaryLineHeight * CGFloat(summaryLineLimit), alignment: .top)
            }
        }
    }

    private var summaryLineHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: .callout).lineHeight
    }

    @ViewBuilder
    private var metadataLine: some View {
        let items = metadataItems
        if !items.isEmpty {
            HStack(spacing: 16) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    HStack(spacing: 6) {
                        if let systemImage = item.systemImage {
                            Image(systemName: systemImage)
                        }
                        Text(item.text)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.brandSecondary)
        }
    }

    @ViewBuilder
    private var genresLine: some View {
        let genres = genreNames
        if !genres.isEmpty {
            HStack(spacing: 12) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                }
            }
            .font(.caption)
            .foregroundStyle(.brandSecondary)
            .lineLimit(1)
        }
    }

    private var displayTitle: String {
        switch media.mediaType {
        case .movie:
            media.title ?? media.name ?? ""
        case .tv, .person:
            media.name ?? media.title ?? ""
        case .none:
            media.title ?? media.name ?? ""
        }
    }

    private var overview: String? {
        media.overview
    }

    private var tagline: String? {
        media.tagline
    }

    private var yearText: String? {
        switch media.mediaType {
        case .movie:
            year(from: media.releaseDate)
        case .tv:
            year(from: media.firstAirDate)
        case .person, .none:
            nil
        }
    }

    private var runtimeText: String? {
        guard let runtime = media.runtime, runtime > 0 else { return nil }
        return TimeInterval(runtime * 60).mediaDurationText()
    }

    private var ratingText: String? {
        guard let voteAverage = media.voteAverage, voteAverage > 0 else { return nil }
        return String(format: "%.1f", locale: .current, voteAverage)
    }

    private var seasonCountText: String? {
        guard media.mediaType == .tv else { return nil }
        let count = media.numberOfSeasons ?? 0
        guard count > 0 else { return nil }
        return String(localized: "media.labels.seasonsCount \(count)")
    }

    private var episodesCountText: String? {
        guard media.mediaType == .tv else { return nil }
        let count = media.numberOfEpisodes ?? 0
        guard count > 0 else { return nil }
        return String(localized: "media.labels.countEpisode \(count)")
    }

    private var metadataItems: [MetadataItem] {
        var items: [MetadataItem] = []
        if let year = yearText {
            items.append(.init(text: year))
        }
        if let runtime = runtimeText {
            items.append(.init(text: runtime))
        }
        if let rating = ratingText {
            items.append(.init(text: rating, systemImage: "star.fill"))
        }
        if let seasons = seasonCountText {
            items.append(.init(text: seasons))
        }
        if let episodes = episodesCountText {
            items.append(.init(text: episodes))
        }
        return items
    }

    private var genreNames: [String] {
        media.genres?.compactMap(\.name).filter { !$0.isEmpty } ?? []
    }

    private struct MetadataItem: Hashable {
        let text: String
        let systemImage: String?

        init(text: String, systemImage: String? = nil) {
            self.text = text
            self.systemImage = systemImage
        }
    }

    private func year(from dateString: String?) -> String? {
        guard let dateString, dateString.count >= 4 else { return nil }
        return String(dateString.prefix(4))
    }
}
