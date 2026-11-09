import Foundation

@MainActor
protocol AccountPreferencesService {
    var subtitleModes: [AccountSubtitleMode] { get }

    func load() async throws -> AccountPreferences
    /// Returns the values stored after the write: a server can adjust other values along with the one changed.
    func apply(_ change: AccountPreferenceChange) async throws -> AccountPreferences
}

/// An account the active profile can edit the preferences of.
struct AccountPreferencesTarget: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let service: any AccountPreferencesService
}
