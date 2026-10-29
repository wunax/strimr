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
    /// Technical badges of the version that would play; defaults to the resolution the item reports.
    var badges: [String]?
    /// Makes a cut-off summary focusable and opens it in full. Left nil where the hero sits above rails that the
    /// summary would steal focus from.
    var onExpandSummary: ((MediaItem) -> Void)?
    /// Lines that keep their room when the item shown has nothing for them. Where the hero sits in the page flow
    /// rather than over it, this keeps the page below still as the hero moves between items.
    var reservedLines: HeroLines = []
    /// Names the regular cut "Standard" when the title is known to have other editions.
    var namesStandardEdition = false

    var body: some View {
        HeroContentTransitionView(item: media) { media in
            MediaHeroDetailsView(
                media: media,
                logoPath: media.preferredLogoPath ?? fallbackLogoPath,
                badges: badges ?? media.playbackResolutionLabel.map { [$0] } ?? [],
                onExpandSummary: onExpandSummary,
                reservedLines: reservedLines,
                namesStandardEdition: namesStandardEdition,
            )
        }
    }
}

struct HeroLines: OptionSet {
    let rawValue: Int

    static let secondaryLabel = HeroLines(rawValue: 1 << 0)
    static let facts = HeroLines(rawValue: 1 << 1)
    static let summary = HeroLines(rawValue: 1 << 2)
}

private struct MediaHeroDetailsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    let media: MediaItem
    let logoPath: String?
    let badges: [String]
    let onExpandSummary: ((MediaItem) -> Void)?
    let reservedLines: HeroLines
    let namesStandardEdition: Bool
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
            } else if reservedLines.contains(.secondaryLabel) {
                lineSpacer(font: .facts.weight(.semibold))
            }

            ZStack(alignment: .leading) {
                if reservedLines.contains(.facts) {
                    // A badge is taller than the text, so it sets the room of a line that may or may not show one.
                    TechBadge(text: "4K").hidden()
                }
                HStack(spacing: 24) {
                    MediaFactsLine(
                        facts: MediaFactsFormatter.facts(for: media, namesStandardEdition: namesStandardEdition),
                        badges: badges,
                    )
                    ratingsLine
                }
            }

            summary
        }
    }

    private func lineSpacer(font: Font) -> some View {
        Text(verbatim: " ")
            .font(font)
            .hidden()
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
            if let onExpandSummary {
                ExpandableHeroSummary(summary: summary, lineLimit: summaryLineLimit) {
                    onExpandSummary(media)
                }
                .frame(minHeight: summaryLineHeight * CGFloat(summaryLineLimit), alignment: .top)
            } else {
                Text(summary)
                    .font(.bodyText)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(summaryLineLimit)
                    .frame(minHeight: summaryLineHeight * CGFloat(summaryLineLimit), alignment: .top)
            }
        } else if reservedLines.contains(.summary) {
            Color.clear
                .frame(height: summaryLineHeight * CGFloat(summaryLineLimit))
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

/// A summary that becomes focusable once it no longer fits its lines, with a "More" hint opening it in full.
private struct ExpandableHeroSummary: View {
    let summary: String
    let lineLimit: Int
    let onExpand: () -> Void

    @State private var visibleHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        Button(action: onExpand) {
            // The hint keeps its room even when hidden so the text wraps the same whether or not it is cut off.
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                Text(summary)
                    .font(.bodyText)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { visibleHeight = $0 }
                    .background(alignment: .topLeading) {
                        Text(summary)
                            .font(.bodyText)
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                    }

                Text("media.detail.summary.more")
                    .eyebrowStyle()
                    .foregroundStyle(.textPrimary)
                    .opacity(isTruncated ? 1 : 0)
            }
        }
        .buttonStyle(HeroSummaryButtonStyle())
        .disabled(!isTruncated)
    }

    private var isTruncated: Bool {
        fullHeight > visibleHeight + 1
    }
}

private struct HeroSummaryButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let inset: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Drawn outside the text so focusing it does not move the hero.
            .padding(inset)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.surfaceRaised)
                    .opacity(isFocused ? 1 : 0)
            }
            .padding(-inset)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: isFocused)
            .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
