import Foundation

extension AccountPreferences {
    init(jellyfinConfiguration configuration: [String: Any]) {
        self.init(
            audioLanguage: AccountLanguageCode.normalized(configuration["AudioLanguagePreference"] as? String),
            // True plays the file's default track whatever its language.
            selectsAudioByLanguage: !(configuration["PlayDefaultAudioTrack"] as? Bool ?? true),
            subtitleLanguage: AccountLanguageCode.normalized(configuration["SubtitleLanguagePreference"] as? String),
            subtitleMode: Self.subtitleMode(jellyfinValue: configuration["SubtitleMode"] as? String),
        )
    }

    private static func subtitleMode(jellyfinValue: String?) -> AccountSubtitleMode {
        switch jellyfinValue {
        case "None": .off
        case "Always": .always
        case "OnlyForced": .onlyForced
        case "Smart": .smart
        default: .fromFile
        }
    }
}

extension AccountPreferenceChange {
    func apply(toJellyfinConfiguration configuration: inout [String: Any]) {
        switch self {
        case let .audioLanguage(language):
            configuration["AudioLanguagePreference"] = language.map(AccountLanguageCode.jellyfinCode) ?? ""
        case let .selectsAudioByLanguage(isEnabled):
            configuration["PlayDefaultAudioTrack"] = !isEnabled
        case let .subtitleLanguage(language):
            configuration["SubtitleLanguagePreference"] = language.map(AccountLanguageCode.jellyfinCode) ?? ""
        case let .subtitleMode(mode):
            configuration["SubtitleMode"] = switch mode {
            case .off, .manual: "None"
            case .fromFile: "Default"
            case .always: "Always"
            case .onlyForced: "OnlyForced"
            case .smart: "Smart"
            }
        }
    }
}

@MainActor
struct JellyfinAccountPreferencesService: AccountPreferencesService {
    let subtitleModes: [AccountSubtitleMode] = [.fromFile, .off, .always, .onlyForced, .smart]

    /// Resolved per call, to share the write queue of the context the server currently uses.
    let context: () throws -> JellyfinAPIContext

    func load() async throws -> AccountPreferences {
        try await AccountPreferences(jellyfinConfiguration: context().userConfiguration())
    }

    func apply(_ change: AccountPreferenceChange) async throws -> AccountPreferences {
        let context = try context()
        try await context.updateUserConfiguration { configuration in
            change.apply(toJellyfinConfiguration: &configuration)
            return true
        }
        return try await AccountPreferences(jellyfinConfiguration: context.userConfiguration())
    }
}
