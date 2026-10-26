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

    /// Horizontal inset of the sections under a detail page's header; tvOS takes it from the safe area.
    static var detailSectionMargin: CGFloat {
        #if os(macOS)
            28
        #elseif os(iOS)
            16
        #else
            0
        #endif
    }

    /// Gap between the chips of a row; tvOS leaves room for the focus lift of `chipAppearance`.
    static var chipSpacing: CGFloat {
        #if os(tvOS)
            16
        #else
            8
        #endif
    }

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

    /// Backdrop height of an iOS detail page: 16:9 of the width so a wide iPad does not crop a 16:9 backdrop, capped so
    /// the title still shows on the first screen.
    static func detailHeroHeight(for containerSize: CGSize) -> CGFloat {
        max(320, min(containerSize.width * 9 / 16, containerSize.height * 0.55))
    }

    /// Corner radius of cards floating over playing video, such as the Up Next prompt.
    static var overlayCornerRadius: CGFloat {
        #if os(tvOS)
            28
        #elseif os(macOS)
            18
        #else
            24
        #endif
    }

    static let tileCornerRadius: CGFloat = 18

    /// Height of capsule action buttons drawn by `actionButtonStyle`; tvOS uses the system button height.
    static var actionButtonHeight: CGFloat {
        #if os(macOS)
            44
        #else
            50
        #endif
    }

    static var castAvatarSize: CGFloat {
        #if os(tvOS)
            176
        #elseif os(macOS)
            112
        #else
            96
        #endif
    }

    /// Wider than the avatar so names and characters wrap less.
    static var castCardWidth: CGFloat {
        castAvatarSize + 24
    }

    /// Room above and below rails for the focused or hovered card to grow into.
    static var railVerticalInset: CGFloat {
        #if os(tvOS)
            20
        #elseif os(macOS)
            16
        #else
            0
        #endif
    }

    static var libraryTileSpacing: CGFloat {
        #if os(tvOS)
            48
        #elseif os(macOS)
            20
        #else
            16
        #endif
    }

    /// One tile per row on iPhone, two or three on iPad and Mac depending on the width, three on tvOS.
    static var libraryGridColumns: [GridItem] {
        #if os(tvOS)
            Array(repeating: GridItem(.flexible(), spacing: libraryTileSpacing, alignment: .top), count: 3)
        #else
            [GridItem(.adaptive(minimum: 300, maximum: 560), spacing: libraryTileSpacing, alignment: .top)]
        #endif
    }

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
