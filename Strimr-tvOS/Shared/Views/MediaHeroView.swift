import SwiftUI
import UIKit

struct MediaHeroBackgroundView: View {
    @Environment(ServerRegistry.self) private var registry
    @Environment(MediaServices.self) private var scopedServices: MediaServices?
    @Environment(SettingsManager.self) private var settingsManager

    let media: MediaItem

    var body: some View {
        HeroBackdropView(
            key: "\(media.id)-\(artworkPath ?? "none")-\(settingsManager.interface.spoilerProtection.rawValue)",
            load: loadBackdrop,
        )
    }

    private var artworkPath: String? {
        if media.isSpoilerProtected(at: settingsManager.interface.spoilerProtection) {
            return media.spoilerProtectedArtworkPath(at: settingsManager.interface.spoilerProtection)
        }
        return media.grandparentArtPath
            ?? media.artPath
            ?? media.grandparentThumbPath
            ?? media.parentThumbPath
            ?? media.thumbPath
    }

    private func loadBackdrop() async -> HeroBackdrop {
        let providerColors = MediaBackdropGradient.colors(for: .playable(media))
        guard let path = artworkPath,
              let services = registry.services(for: .playable(media), scoped: scopedServices),
              let resource = try? await services.artwork.artwork(path: path, width: 3840, height: 2160)
        else {
            return HeroBackdrop(colors: providerColors)
        }

        await ArtworkResourceView.preload(resource)
        if providerColors.count == 4 {
            return HeroBackdrop(resource: resource, colors: providerColors)
        }
        let sampledColors = await (try? ImageCornerColorSampler.colors(from: resource)) ?? []
        return HeroBackdrop(resource: resource, colors: sampledColors.count == 4 ? sampledColors : [])
    }
}

struct MediaHeroContentView: View {
    let media: MediaItem

    var body: some View {
        HeroContentTransitionView(item: media) { media in
            MediaHeroDetailsView(media: media)
        }
    }
}

private struct MediaHeroDetailsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    let media: MediaItem
    private let summaryLineLimit = 3

    var body: some View {
        heroContent
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(media.primaryLabel)
                .font(.title2.bold())
                .lineLimit(2)

            if let secondary = media.secondaryLabel, media.type != .movie, media.type != .series {
                Text(secondary)
                    .font(.headline)
                    .foregroundStyle(.brandSecondary)
            }

            metadataLine
            ratingsLine
            genresLine

            if media.shouldHideSpoilerSummary(at: settingsManager.interface.spoilerProtection) {
                Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
                    .font(.callout)
                    .foregroundStyle(.brandSecondary)
                    .lineLimit(summaryLineLimit)
                    .frame(minHeight: summaryLineHeight * CGFloat(summaryLineLimit), alignment: .top)
            } else if let summary = media.summary, !summary.isEmpty {
                Text(summary)
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
                    Text(items[index])
                }
            }
            .font(.subheadline)
            .foregroundStyle(.brandSecondary)
        }
    }

    @ViewBuilder
    private var ratingsLine: some View {
        if !media.ratings.isEmpty {
            HStack(spacing: 16) {
                ForEach(Array(media.ratings.enumerated()), id: \.offset) { _, rating in
                    MediaRatingLabel(rating: rating)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.brandSecondary)
        }
    }

    @ViewBuilder
    private var genresLine: some View {
        let genres = media.genres
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

    private var metadataItems: [String] {
        var items: [String] = []
        if let tertiary = media.tertiaryLabel {
            items.append(tertiary)
        }
        if let year = yearText {
            items.append(year)
        }
        if let runtime = runtimeText {
            items.append(runtime)
        }
        if let contentRating = media.contentRating {
            items.append(contentRating)
        }
        return items
    }

    private var runtimeText: String? {
        guard let duration = media.duration else { return nil }
        return duration.mediaDurationText()
    }

    private var yearText: String? {
        media.year.map(String.init)
    }
}
