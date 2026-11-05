import Foundation

nonisolated struct TrackerAccountSettings: Codable, Equatable, Sendable {
    var username: String?
    var isEnabled = true
    var excludedLibraries: Set<String> = []
    var needsReconnect = false
}

/// Per-profile tracker accounts: tokens in the secure store, everything else in `UserDefaults`.
@MainActor
final class TrackerAccountStore {
    private let defaults: UserDefaults
    private let secureStore: any SecureStore

    init(
        userDefaults: UserDefaults = .standard,
        secureStore: (any SecureStore)? = nil,
    ) {
        defaults = userDefaults
        self.secureStore = secureStore ?? Keychain(service: Bundle.main.bundleIdentifier!)
    }

    private func sessionKey(_ service: TrackerService, profileID: String) -> String {
        "strimr.trackers.\(service.rawValue).\(profileID)"
    }

    private func settingsKey(_ service: TrackerService, profileID: String) -> String {
        "strimr.trackers.settings.\(service.rawValue).\(profileID)"
    }

    func session(_ service: TrackerService, profileID: String) -> TrackerSession? {
        do {
            guard let json = try secureStore.string(forKey: sessionKey(service, profileID: profileID)) else {
                return nil
            }
            return try JSONDecoder().decode(TrackerSession.self, from: Data(json.utf8))
        } catch {
            ErrorReporter.capture(error)
            return nil
        }
    }

    func saveSession(_ session: TrackerSession, service: TrackerService, profileID: String) {
        do {
            let data = try JSONEncoder().encode(session)
            try secureStore.setString(
                String(decoding: data, as: UTF8.self),
                forKey: sessionKey(service, profileID: profileID),
            )
        } catch {
            ErrorReporter.capture(error)
        }
    }

    func deleteSession(_ service: TrackerService, profileID: String) {
        do {
            try secureStore.deleteValue(forKey: sessionKey(service, profileID: profileID))
        } catch {
            ErrorReporter.capture(error)
        }
    }

    func settings(_ service: TrackerService, profileID: String) -> TrackerAccountSettings {
        guard let data = defaults.data(forKey: settingsKey(service, profileID: profileID)),
              let settings = try? JSONDecoder().decode(TrackerAccountSettings.self, from: data)
        else { return TrackerAccountSettings() }
        return settings
    }

    func saveSettings(_ settings: TrackerAccountSettings, service: TrackerService, profileID: String) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: settingsKey(service, profileID: profileID))
    }

    func removeAccount(_ service: TrackerService, profileID: String) {
        deleteSession(service, profileID: profileID)
        defaults.removeObject(forKey: settingsKey(service, profileID: profileID))
    }
}
