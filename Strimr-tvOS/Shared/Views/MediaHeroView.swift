import SwiftUI
import UIKit

struct MediaHeroBackgroundView: View {
    @Environment(MediaServices.self) private var mediaServices
    @Environment(SettingsManager.self) private var settingsManager

    let media: MediaItem

    @State private var imageResource: ArtworkResource?
    @State private var imageSourcePath: String?
    @State private var sampledBackdropColors: [Color] = []

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MediaBackdropGradient(colors: backdropColors)
                    .ignoresSafeArea()

                ArtworkResourceView(resource: imageSourcePath == artworkPath ? imageResource : nil)
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
        .task(id: "\(media.id)-\(artworkPath ?? "none")-\(settingsManager.interface.spoilerProtection.rawValue)") {
            await loadImage()
        }
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

    private var backdropColors: [Color] {
        let providerColors = MediaBackdropGradient.colors(for: .playable(media))
        if providerColors.count == 4 {
            return providerColors
        }
        return sampledBackdropColors
    }

    private func loadImage() async {
        let path = artworkPath
        guard let path else {
            imageResource = nil
            imageSourcePath = nil
            sampledBackdropColors = []
            return
        }

        do {
            let resource = try await mediaServices.artwork.artwork(
                path: path,
                width: 3840,
                height: 2160
            )
            guard !Task.isCancelled, artworkPath == path else { return }
            imageResource = resource
            imageSourcePath = path

            let providerColors = MediaBackdropGradient.colors(for: .playable(media))
            guard providerColors.count != 4, let resource else {
                sampledBackdropColors = []
                return
            }

            let colors = try await ImageCornerColorSampler.colors(from: resource)
            guard !Task.isCancelled, artworkPath == path, colors.count == 4 else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                sampledBackdropColors = colors
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation, artworkPath == path else { return }
            imageResource = nil
            imageSourcePath = path
        }
    }
}

struct MediaHeroContentView: View {
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
                ForEach(media.ratings.indices, id: \.self) { index in
                    MediaRatingLabel(rating: media.ratings[index])
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
