import CoreGraphics
import Foundation

/// An image of a media that the server administrator can replace.
enum EditableArtworkKind: String, CaseIterable, Hashable, Sendable {
    case poster
    case background
    case logo
    /// 16:9 image: an episode's only image, or the landscape art of a Jellyfin movie or series.
    case thumb
    case banner

    var title: String {
        switch self {
        case .poster: String(localized: "media.artwork.kind.poster")
        case .background: String(localized: "media.artwork.kind.background")
        case .logo: String(localized: "media.artwork.kind.logo")
        case .thumb: String(localized: "media.artwork.kind.thumb")
        case .banner: String(localized: "media.artwork.kind.banner")
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .poster: 2 / 3
        case .background, .thumb, .logo: 16 / 9
        case .banner: 1000 / 185
        }
    }
}

struct ArtworkOption: Identifiable, Hashable, Sendable {
    let id: String
    let previewURL: URL
    /// What the server is sent back to choose the image; for Plex, possibly a path on the server.
    let source: String
    /// nil for an image stored on the server, local or uploaded.
    let provider: String?
    let width: Int?
    let height: Int?
    /// nil for an image without text.
    let language: String?
    var isSelected: Bool
}

nonisolated enum ArtworkLanguageFilter {
    /// The images in `language` or without text, plus the current one whatever its language.
    static func visible(
        _ options: [ArtworkOption],
        language: String?,
        includeAllLanguages: Bool,
    ) -> [ArtworkOption] {
        guard !includeAllLanguages else { return options }
        return options.filter { $0.isSelected || matches($0.language, language) }
    }

    static func hasOtherLanguages(_ options: [ArtworkOption], language: String?) -> Bool {
        options.contains { !matches($0.language, language) }
    }

    /// The app's language, in the two-letter form providers use.
    static var appLanguage: String? {
        Bundle.main.preferredLocalizations.first.map(baseLanguage)
    }

    private static func matches(_ optionLanguage: String?, _ language: String?) -> Bool {
        guard let optionLanguage, !optionLanguage.isEmpty else { return true }
        guard let language else { return false }
        return baseLanguage(optionLanguage) == baseLanguage(language)
    }

    private static func baseLanguage(_ code: String) -> String {
        String(code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }
}
