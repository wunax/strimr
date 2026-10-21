import SwiftUI

enum LayoutMetrics {
    /// Horizontal inset of pages; on tvOS the leading side comes from the safe area, so only the trailing one is used.
    static var pageMargin: CGFloat {
        #if os(tvOS)
            24
        #else
            16
        #endif
    }

    static let cardCornerRadius = MediaArtworkMetrics.cornerRadius

    static var cardLabelSpacing: CGFloat {
        #if os(tvOS)
            20
        #else
            8
        #endif
    }

    /// Largest box a title logo may fill in a hero; on tvOS, small enough for the hero details to end above the rails.
    static var heroLogoMaxSize: CGSize {
        #if os(tvOS)
            CGSize(width: 480, height: 120)
        #else
            CGSize(width: 320, height: 120)
        #endif
    }

    /// Room above and below tvOS rails for the focused card to grow into.
    static let tvRailVerticalInset: CGFloat = 20

    static func railSpacing(for layout: MediaCarousel.Layout) -> CGFloat {
        switch layout {
        case .portrait:
            #if os(tvOS)
                28
            #else
                12
            #endif
        case .landscape:
            #if os(tvOS)
                32
            #else
                16
            #endif
        }
    }

    /// Card height before the poster size setting is applied.
    static func baseCardHeight(for layout: MediaCarousel.Layout, sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        switch layout {
        case .portrait:
            #if os(tvOS)
                320
            #elseif os(macOS)
                260
            #else
                sizeClass == .compact ? 180 : 240
            #endif
        case .landscape:
            #if os(tvOS)
                180
            #elseif os(macOS)
                140
            #else
                sizeClass == .compact ? 90 : 124
            #endif
        }
    }

    static func cardSize(
        for layout: MediaCarousel.Layout,
        sizeClass: UserInterfaceSizeClass?,
        posterScale: CGFloat,
    ) -> CGSize {
        let height = baseCardHeight(for: layout, sizeClass: sizeClass) * posterScale
        switch layout {
        case .portrait:
            return CGSize(width: height * 2 / 3, height: height)
        case .landscape:
            return CGSize(width: height * 16 / 9, height: height)
        }
    }
}

extension EnvironmentValues {
    /// Horizontal padding of the page around a rail, which the rail scrolls under.
    @Entry var railPageMargin: CGFloat = LayoutMetrics.pageMargin
}

extension View {
    /// Stretches a horizontal rail across the page margins to the screen edges while its first card still lines up
    /// with the page. The card clipped at the trailing edge hints that the rail scrolls. On tvOS the leading inset
    /// comes from the safe area and rails do not clip, so only the trailing side is stretched.
    func railBleed(pageMargin: CGFloat) -> some View {
        #if os(tvOS)
            padding(.trailing, -pageMargin)
        #else
            contentMargins(.leading, pageMargin, for: .scrollContent)
                .padding(.horizontal, -pageMargin)
        #endif
    }
}
