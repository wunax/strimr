import AetherEngine
import Foundation

nonisolated enum AutomaticSubtitleSearch {
    struct ExistingSubtitle: Equatable {
        let language: String?
        let isForced: Bool
    }

    /// Nil when subtitles should stay as they are. A choice made for this media or series comes before the account.
    static func language(
        remembered: MediaSubtitlePreference?,
        account: AccountPreferences?,
        deviceLanguage: String,
    ) -> String? {
        switch remembered {
        case .off:
            return nil
        case let .track(_, language, _, _, isForced, _):
            if isForced {
                return nil
            }
            if let code = AccountLanguageCode.code(fromTrackLanguage: language) {
                return code
            }
        case .serverDefault, nil:
            break
        }

        if account?.subtitleMode == .off || account?.subtitleMode == .onlyForced {
            return nil
        }
        return account?.subtitleLanguage ?? AccountLanguageCode.normalized(deviceLanguage)
    }

    /// An audio track of unknown language could already be in `language`, so it does not justify a download. Forced
    /// tracks only cover part of the dialogue and do not count.
    static func isMissing(language: String, audioLanguage: String?, subtitles: [ExistingSubtitle]) -> Bool {
        guard let audio = AccountLanguageCode.code(fromTrackLanguage: audioLanguage), audio != language else {
            return false
        }
        return !subtitles.contains { subtitle in
            !subtitle.isForced && AccountLanguageCode.code(fromTrackLanguage: subtitle.language) == language
        }
    }

    /// A new track without a language is accepted, since the server may not tag what it just added.
    static func installedSubtitle(
        in refreshed: [PlayerExternalSubtitle],
        previousURLs: Set<URL>,
        language: String,
    ) -> PlayerExternalSubtitle? {
        refreshed.first { subtitle in
            guard !previousURLs.contains(subtitle.track.url), !subtitle.track.isForced else { return false }
            guard let trackLanguage = AccountLanguageCode.code(fromTrackLanguage: subtitle.track.language) else {
                return true
            }
            return trackLanguage == language
        }
    }
}

enum AutomaticSubtitleSearchOutcome {
    case attached(PlayerExternalSubtitle, language: String)
    case notFound(language: String)
    case failed(language: String)

    var toast: Toast {
        switch self {
        case let .attached(_, language):
            Toast(
                style: .success,
                title: String(localized: "player.automaticSubtitles.added \(Self.name(of: language))"),
                message: String(localized: "player.automaticSubtitles.added.message"),
            )
        case let .notFound(language):
            Toast(
                style: .failure,
                title: String(localized: "player.automaticSubtitles.notFound \(Self.name(of: language))"),
            )
        case let .failed(language):
            Toast(
                style: .failure,
                title: String(localized: "player.automaticSubtitles.failed \(Self.name(of: language))"),
            )
        }
    }

    private static func name(of language: String) -> String {
        AccountLanguageCode.displayName(language)
    }
}
