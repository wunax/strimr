import SwiftUI
import UIKit

struct SeerrHeroBackgroundView: View {
    let media: SeerrMedia

    @State private var imageURL: URL?
    @State private var backdropColors: [Color] = []
    @State private var gradientSourceURL: URL?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MediaBackdropGradient(colors: backdropColors)
                    .ignoresSafeArea()

                HeroImageView(imageURL: imageURL)
                    .frame(
                        width: (proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing) * 0.66,
                        height: (proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom) * 0.66,
                    )
                    .clipped()
                    .overlay(Color.black.opacity(0.2))
                    .mask(HeroMaskView())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .ignoresSafeArea()
            }
        }
        .task(id: media.id) {
            await loadImages()
        }
    }

    private var heroImageURL: URL? {
        TMDBImageService.backdropURL(path: media.backdropPath, width: 1400)
            ?? TMDBImageService.posterURL(path: media.posterPath, width: 780)
    }

    private var gradientImageURL: URL? {
        TMDBImageService.backdropURL(path: media.backdropPath, width: 300)
            ?? TMDBImageService.posterURL(path: media.posterPath, width: 300)
    }

    private func loadImages() async {
        imageURL = heroImageURL

        guard let gradientURL = gradientImageURL else {
            gradientSourceURL = nil
            backdropColors = []
            return
        }
        guard gradientSourceURL != gradientURL else { return }
        gradientSourceURL = gradientURL

        do {
            let (data, _) = try await URLSession.shared.data(from: gradientURL)
            let colors = ImageCornerColorSampler.colors(from: data)
            backdropColors = colors.count == 4 ? colors : []
        } catch {
            backdropColors = []
        }
    }
}

struct SeerrHeroContentView: View {
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
