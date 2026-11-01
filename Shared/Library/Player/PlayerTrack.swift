import Foundation

struct PlayerTrack: Identifiable, Hashable {
    enum TrackType: String {
        case audio
        case subtitle = "sub"
        case video
    }

    let id: Int
    let ffIndex: Int?
    let providerStreamID: Int?
    let type: TrackType
    let title: String?
    let language: String?
    let codec: String?
    let isDefault: Bool
    let isForced: Bool
    let isHearingImpaired: Bool
    let isCommentary: Bool
    let isExternal: Bool
    let isSelected: Bool

    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }

        if let language, !language.isEmpty {
            return language.uppercased()
        }

        if let codec, !codec.isEmpty {
            return codec.uppercased()
        }

        return "Track \(id)"
    }
}

extension [PlayerTrack] {
    /// The track to pick for a language from a link, nil when none is in that language. The caller then keeps
    /// the selection the app made itself (remembered, server or file default).
    ///
    /// Codes are compared as ISO 639-1, so `fr`, `fra` and `fre` match each other. With several tracks in the
    /// language, a regular one beats commentary, hearing impaired and forced ones, then the file's default
    /// beats the rest, then the file's order decides.
    func best(forLanguage language: String) -> PlayerTrack? {
        guard let target = SkipBackSubtitles.normalizedLanguage(language) else { return nil }
        return enumerated()
            .filter { SkipBackSubtitles.normalizedLanguage($0.element.language) == target }
            .min { lhs, rhs in
                (lhs.element.selectionPenalty, lhs.offset) < (rhs.element.selectionPenalty, rhs.offset)
            }?
            .element
    }
}

private extension PlayerTrack {
    var selectionPenalty: Int {
        (isCommentary ? 8 : 0) + (isHearingImpaired ? 4 : 0) + (isForced ? 2 : 0) + (isDefault ? 0 : 1)
    }
}
