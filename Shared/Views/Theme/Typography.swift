import SwiftUI

/// Text roles shared by every screen. iOS and macOS follow Dynamic Type; tvOS has no text size preference, so sizes
/// are fixed there.
extension Font {
    static var heroTitle: Font {
        #if os(tvOS)
            .system(size: 56, weight: .bold)
        #else
            .largeTitle.bold()
        #endif
    }

    static var sectionTitle: Font {
        #if os(tvOS)
            .system(size: 36, weight: .semibold)
        #else
            .title3.weight(.semibold)
        #endif
    }

    static var tileTitle: Font {
        #if os(tvOS)
            .system(size: 38, weight: .bold)
        #else
            .title2.bold()
        #endif
    }

    /// Title of a full-width list row, such as a library item or a folder in list mode.
    static var rowTitle: Font {
        #if os(tvOS)
            .system(size: 30, weight: .semibold)
        #else
            .headline
        #endif
    }

    static var cardTitle: Font {
        #if os(tvOS)
            .system(size: 24, weight: .medium)
        #else
            .subheadline.weight(.semibold)
        #endif
    }

    static var cardMetadata: Font {
        #if os(tvOS)
            .system(size: 20, weight: .regular)
        #else
            .caption
        #endif
    }

    static var bodyText: Font {
        #if os(tvOS)
            .system(size: 26, weight: .regular)
        #else
            .body
        #endif
    }

    static var facts: Font {
        #if os(tvOS)
            .system(size: 24, weight: .regular)
        #else
            .subheadline
        #endif
    }

    static var eyebrow: Font {
        #if os(tvOS)
            .system(size: 18, weight: .semibold)
        #else
            .caption2.weight(.semibold)
        #endif
    }

    static var badge: Font {
        #if os(tvOS)
            .system(size: 18, weight: .bold)
        #else
            .caption2.weight(.bold)
        #endif
    }
}

extension View {
    func eyebrowStyle() -> some View {
        #if os(tvOS)
            font(.eyebrow).tracking(1.2).textCase(.uppercase)
        #else
            font(.eyebrow).tracking(1).textCase(.uppercase)
        #endif
    }
}
