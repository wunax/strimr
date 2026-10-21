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
        let services = registry.services(for: .playable(media), scoped: scopedServices)
        async let backdrop = loadBackdropImage(services: services)
        // Loaded alongside the backdrop so the hero shows the logo from its first frame instead of swapping it in.
        if let services, settingsManager.interface.showsTitleLogo {
            await TitleLogoView.preload(media: media, services: services, maxSize: LayoutMetrics.heroLogoMaxSize)
        }
        return await backdrop
    }

    private func loadBackdropImage(services: MediaServices?) async -> HeroBackdrop {
        let providerColors = MediaBackdropGradient.colors(for: .playable(media))
        guard let path = artworkPath,
              let services,
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
    /// Logo to use when the item has none of its own, e.g. the series logo loaded by the detail page.
    var fallbackLogoPath: String?
    var starring: String?
    /// Technical badges of the version that would play; defaults to the resolution the item reports.
    var badges: [String]?

    var body: some View {
        HeroContentTransitionView(item: media) { media in
            MediaHeroDetailsView(
                media: media,
                logoPath: media.preferredLogoPath ?? fallbackLogoPath,
                starring: starring,
                badges: badges ?? media.playbackResolutionLabel.map { [$0] } ?? [],
            )
        }
    }
}

private struct MediaHeroDetailsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    let media: MediaItem
    let logoPath: String?
    let starring: String?
    let badges: [String]
    private let summaryLineLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Fixed height so a tall logo or a two-line title never moves what follows during hero transitions.
            TitleLogoView(media: media, logoPath: logoPath, maxSize: LayoutMetrics.heroLogoMaxSize)
                .frame(height: LayoutMetrics.heroLogoMaxSize.height, alignment: .bottomLeading)

            if let secondary = media.secondaryLabel, media.type != .movie, media.type != .series {
                Text(secondary)
                    .font(.facts.weight(.semibold))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
            }

            MediaFactsLine(facts: MediaFactsFormatter.facts(for: media), badges: badges)
            ratingsLine
            summary

            if let starring {
                Text(starring)
                    .font(.facts)
                    .foregroundStyle(.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if media.shouldHideSpoilerSummary(at: settingsManager.interface.spoilerProtection) {
            Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
                .font(.bodyText)
                .foregroundStyle(.textSecondary)
                .lineLimit(summaryLineLimit)
                .frame(minHeight: summaryLineHeight * CGFloat(summaryLineLimit), alignment: .top)
        } else if let summary = media.summary, !summary.isEmpty {
            Text(summary)
                .font(.bodyText)
                .foregroundStyle(.textSecondary)
                .lineLimit(summaryLineLimit)
                .frame(minHeight: summaryLineHeight * CGFloat(summaryLineLimit), alignment: .top)
        }
    }

    private var summaryLineHeight: CGFloat {
        UIFont.systemFont(ofSize: 26).lineHeight
    }

    @ViewBuilder
    private var ratingsLine: some View {
        if !media.ratings.isEmpty {
            HStack(spacing: 16) {
                ForEach(Array(media.ratings.enumerated()), id: \.offset) { _, rating in
                    MediaRatingLabel(rating: rating)
                }
            }
            .font(.facts)
            .foregroundStyle(.textSecondary)
        }
    }
}
