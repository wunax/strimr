import Foundation

nonisolated enum AccountSubtitleMode: String, CaseIterable, Hashable, Sendable {
    /// Jellyfin: subtitles never turn on by themselves.
    case off
    /// Plex: subtitles stay as last chosen by hand, which is not the same as off.
    case manual
    /// Jellyfin: follows the track the file flags as default.
    case fromFile
    case always
    case onlyForced
    case smart

    var title: String {
        switch self {
        case .off:
            String(localized: "settings.accountPreferences.subtitleMode.off")
        case .manual:
            String(localized: "settings.accountPreferences.subtitleMode.manual")
        case .fromFile:
            String(localized: "settings.accountPreferences.subtitleMode.fromFile")
        case .always:
            String(localized: "settings.accountPreferences.subtitleMode.always")
        case .onlyForced:
            String(localized: "settings.accountPreferences.subtitleMode.onlyForced")
        case .smart:
            String(localized: "settings.accountPreferences.subtitleMode.smart")
        }
    }
}

/// Audio and subtitle defaults stored on a Plex or Jellyfin account. The server applies them when it picks the tracks
/// of an item, so the app only reads and writes them. Languages are ISO 639-1 codes.
nonisolated struct AccountPreferences: Equatable, Sendable {
    var audioLanguage: String?
    var selectsAudioByLanguage: Bool
    var subtitleLanguage: String?
    var subtitleMode: AccountSubtitleMode

    static let empty = AccountPreferences(
        audioLanguage: nil,
        selectsAudioByLanguage: false,
        subtitleLanguage: nil,
        subtitleMode: .fromFile,
    )

    func applying(_ change: AccountPreferenceChange) -> AccountPreferences {
        var updated = self
        switch change {
        case let .audioLanguage(language):
            updated.audioLanguage = language
        case let .selectsAudioByLanguage(isEnabled):
            updated.selectsAudioByLanguage = isEnabled
        case let .subtitleLanguage(language):
            updated.subtitleLanguage = language
        case let .subtitleMode(mode):
            updated.subtitleMode = mode
        }
        return updated
    }
}

nonisolated enum AccountPreferenceChange: Equatable, Sendable {
    case audioLanguage(String?)
    case selectsAudioByLanguage(Bool)
    case subtitleLanguage(String?)
    case subtitleMode(AccountSubtitleMode)
}

nonisolated enum AccountLanguageCode {
    /// Foundation only knows the terminologic ISO 639-2 codes (`fra`), while Jellyfin and many files use the
    /// bibliographic ones (`fre`).
    private static let bibliographicByAlpha2 = [
        "bo": "tib", "cs": "cze", "cy": "wel", "de": "ger", "el": "gre", "eu": "baq", "fa": "per",
        "fr": "fre", "hy": "arm", "is": "ice", "ka": "geo", "mi": "mao", "mk": "mac", "ms": "may",
        "my": "bur", "nl": "dut", "ro": "rum", "sk": "slo", "sq": "alb", "zh": "chi",
    ]
    private static let alpha2ByBibliographic = Dictionary(
        uniqueKeysWithValues: bibliographicByAlpha2.map { ($0.value, $0.key) },
    )

    /// The ISO 639-1 code of a stored value when it has one (`fre`, `fra`, `fr-FR` -> `fr`). Empty means no preference.
    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let code = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init)
        guard let code, !code.isEmpty else { return nil }
        return alpha2ByBibliographic[code] ?? Locale.LanguageCode(code).identifier(.alpha2) ?? code
    }

    private static let undeterminedCodes: Set<String> = ["und", "mis", "mul", "zxx"]

    private static let codesByLanguageName: [String: String] = {
        var codes: [String: String] = [:]
        for code in Locale.LanguageCode.isoLanguageCodes.map(\.identifier) where code.count == 2 {
            let locales = [Locale(identifier: "en"), Locale.current, Locale(identifier: code)]
            for locale in locales {
                if let name = locale.localizedString(forLanguageCode: code)?.lowercased(), codes[name] == nil {
                    codes[name] = code
                }
            }
        }
        return codes
    }()

    /// The ISO 639-1 code of a track's language, which Plex often gives as a name (`French`, `Français (Canada)`).
    /// Nil when it is empty, undetermined or not a known language.
    static func code(fromTrackLanguage value: String?) -> String? {
        let base = value?.split(separator: "(").first.map(String.init)
        guard let code = normalized(base), !undeterminedCodes.contains(code) else { return nil }
        return Locale.LanguageCode(code).isISOLanguage ? code : codesByLanguageName[code]
    }

    /// Jellyfin stores ISO 639-2 codes, the bibliographic ones in its own language list.
    static func jellyfinCode(_ code: String) -> String {
        bibliographicByAlpha2[code] ?? Locale.LanguageCode(code).identifier(.alpha3) ?? code
    }

    static func displayName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
