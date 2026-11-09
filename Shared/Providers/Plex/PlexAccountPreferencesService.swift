import Foundation

extension AccountPreferences {
    init(plexProfile profile: PlexAccountProfile) {
        self.init(
            audioLanguage: AccountLanguageCode.normalized(profile.defaultAudioLanguage),
            selectsAudioByLanguage: profile.autoSelectAudio ?? true,
            subtitleLanguage: AccountLanguageCode.normalized(profile.defaultSubtitleLanguage),
            subtitleMode: Self.subtitleMode(plexValue: profile.autoSelectSubtitle),
        )
    }

    private static func subtitleMode(plexValue: Int?) -> AccountSubtitleMode {
        switch plexValue {
        case 1: .smart
        case 2: .always
        default: .manual
        }
    }
}

extension AccountPreferenceChange {
    var plexQueryItems: [URLQueryItem] {
        switch self {
        case let .audioLanguage(language):
            [URLQueryItem(name: "defaultAudioLanguage", value: language ?? "")]
        case let .selectsAudioByLanguage(isEnabled):
            // Plex Web also turns automatic subtitles off with automatic audio, to keep both settings consistent.
            [URLQueryItem(name: "autoSelectAudio", value: isEnabled ? "1" : "0")]
                + (isEnabled ? [] : [URLQueryItem(name: "autoSelectSubtitle", value: "0")])
        case let .subtitleLanguage(language):
            [URLQueryItem(name: "defaultSubtitleLanguage", value: language ?? "")]
        case let .subtitleMode(mode):
            [URLQueryItem(name: "autoSelectSubtitle", value: Self.plexValue(mode))]
        }
    }

    private static func plexValue(_ mode: AccountSubtitleMode) -> String {
        switch mode {
        case .smart: "1"
        case .always: "2"
        case .off, .manual, .fromFile, .onlyForced: "0"
        }
    }
}

@MainActor
struct PlexAccountPreferencesService: AccountPreferencesService {
    let subtitleModes: [AccountSubtitleMode] = [.manual, .smart, .always]

    /// The token of the profile's own Plex user: the account token would edit the preferences of the account owner.
    let token: () async throws -> String
    var session: URLSession = .shared

    func load() async throws -> AccountPreferences {
        try await AccountPreferences(plexProfile: repository().getAccountProfile())
    }

    func apply(_ change: AccountPreferenceChange) async throws -> AccountPreferences {
        let repository = try await repository()
        try await repository.updateAccountProfile(queryItems: change.plexQueryItems)
        return try await AccountPreferences(plexProfile: repository.getAccountProfile())
    }

    private func repository() async throws -> UserRepository {
        let token = try await token()
        let context = PlexAPIContext(session: session)
        await context.waitForBootstrap()
        context.setAuthToken(token)
        return UserRepository(context: context)
    }
}
