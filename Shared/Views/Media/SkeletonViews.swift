import SwiftUI

struct PosterSkeletonCard: View {
    var width: CGFloat?
    var showsLabels = true

    var body: some View {
        SkeletonCard(layout: .portrait, width: width, showsLabels: showsLabels)
    }
}

struct LandscapeSkeletonCard: View {
    var width: CGFloat?
    var showsLabels = true

    var body: some View {
        SkeletonCard(layout: .landscape, width: width, showsLabels: showsLabels)
    }
}

struct CarouselSkeleton: View {
    let layout: MediaCarousel.Layout
    var count = 6
    var showsLabels = true

    @Environment(\.railPageMargin) private var pageMargin

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: LayoutMetrics.railSpacing(for: layout)) {
                ForEach(0 ..< count, id: \.self) { _ in
                    SkeletonCard(layout: layout, width: nil, showsLabels: showsLabels)
                }
            }
            #if os(tvOS)
            .padding(.vertical, LayoutMetrics.railVerticalInset)
            #endif
        }
        .scrollDisabled(true)
        .railBleed(pageMargin: pageMargin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("common.loading"))
    }
}

struct SectionSkeleton: View {
    var layout: MediaCarousel.Layout = .portrait
    var count = 6
    var showsLabels = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonLine(font: .sectionTitle, fraction: 1)
                .frame(width: sectionTitleWidth)
            CarouselSkeleton(layout: layout, count: count, showsLabels: showsLabels)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("common.loading"))
    }

    private var sectionTitleWidth: CGFloat {
        #if os(tvOS)
            320
        #else
            160
        #endif
    }
}

private struct SkeletonCard: View {
    let layout: MediaCarousel.Layout
    let width: CGFloat?
    let showsLabels: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        let size = resolvedSize
        VStack(alignment: .leading, spacing: LayoutMetrics.cardLabelSpacing) {
            RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(.surfaceSubtle)
                .frame(width: size.width, height: size.height)

            if showsLabels {
                VStack(alignment: .leading, spacing: 4) {
                    SkeletonLine(font: .cardTitle, fraction: 0.8)
                    SkeletonLine(font: .cardMetadata, fraction: 0.5)
                }
            }
        }
        .frame(width: size.width, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("common.loading"))
    }

    private var resolvedSize: CGSize {
        let defaultSize = LayoutMetrics.cardSize(
            for: layout,
            sizeClass: sizeClass,
            posterScale: settingsManager.interface.posterSize.scale,
        )
        guard let width else { return defaultSize }
        return CGSize(width: width, height: width * defaultSize.height / defaultSize.width)
    }
}

/// A bar as tall as one line of `font`, so the skeleton matches the height of the text it stands in for.
struct SkeletonLine: View {
    let font: Font
    let fraction: CGFloat

    var body: some View {
        Text(verbatim: " ")
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.surfaceSubtle)
                        .frame(width: proxy.size.width * fraction, height: proxy.size.height * 0.7)
                        .frame(maxHeight: .infinity)
                }
            }
    }
}

/// Placeholder for a page of rails while its first rows load.
struct RailsSkeleton: View {
    var showsLabels = true

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionSkeleton(layout: .landscape, count: 4, showsLabels: showsLabels)
            SectionSkeleton(layout: .portrait, showsLabels: showsLabels)
            SectionSkeleton(layout: .portrait, showsLabels: showsLabels)
        }
    }
}

/// Poster placeholders to drop into a `PosterGrid` while its first page loads.
struct PosterSkeletonCards: View {
    let width: CGFloat
    var count = 12
    var showsLabels = true

    var body: some View {
        ForEach(0 ..< count, id: \.self) { _ in
            PosterSkeletonCard(width: width, showsLabels: showsLabels)
        }
    }
}
