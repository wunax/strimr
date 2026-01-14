import Foundation

enum AuthErrorMapper {
    static func signInMessage(for error: Error) -> String {
        if let plexError = error as? PlexAPIError {
            return signInMessage(for: plexError)
        }
        return String(localized: "signIn.error.startFailed")
    }

    static func profileLoadMessage(for error: Error) -> String {
        if let plexError = error as? PlexAPIError {
            return profileLoadMessage(for: plexError)
        }
        return String(localized: "auth.profile.error.loadFailed")
    }

    static func profileSwitchMessage(for error: Error) -> String {
        if let plexError = error as? PlexAPIError {
            return profileSwitchMessage(for: plexError)
        }
        return String(localized: "auth.profile.error.switchFailed")
    }

    private static func signInMessage(for _: PlexAPIError) -> String {
        String(localized: "signIn.error.startFailed")
    }

    private static func profileLoadMessage(for _: PlexAPIError) -> String {
        String(localized: "auth.profile.error.loadFailed")
    }

    private static func profileSwitchMessage(for _: PlexAPIError) -> String {
        String(localized: "auth.profile.error.switchFailed")
    }
}
