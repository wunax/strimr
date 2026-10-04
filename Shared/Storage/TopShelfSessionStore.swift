import Foundation

#if os(tvOS)
    struct TopShelfServerCredentials {
        let session: TopShelfStoredSession
        let token: String
    }

    /// Shares the servers of the active profile with the Top Shelf extension: the list in the app group, one token per
    /// server in the shared Keychain.
    struct TopShelfSessionStore {
        private let defaults = UserDefaults(suiteName: TopShelfSessions.appGroup)

        private var keychain: Keychain? {
            guard let accessGroup = Bundle.main.object(forInfoDictionaryKey: "TopShelfKeychainAccessGroup") as? String,
                  !accessGroup.isEmpty
            else { return nil }
            return Keychain(service: TopShelfSessions.keychainService, accessGroup: accessGroup)
        }

        func save(_ credentials: [TopShelfServerCredentials]) throws {
            guard let keychain else { return }
            let previous = storedSessions()
            for credential in credentials {
                try keychain.setString(credential.token, forKey: credential.session.tokenKey)
            }
            let kept = Set(credentials.map(\.session.tokenKey))
            for session in previous where !kept.contains(session.tokenKey) {
                try? keychain.deleteValue(forKey: session.tokenKey)
            }
            try defaults?.set(JSONEncoder().encode(credentials.map(\.session)), forKey: TopShelfSessions.sessionsKey)
            removeLegacyEntries(keychain: keychain)
        }

        func clear() {
            if let keychain {
                for session in storedSessions() {
                    try? keychain.deleteValue(forKey: session.tokenKey)
                }
                removeLegacyEntries(keychain: keychain)
            }
            defaults?.removeObject(forKey: TopShelfSessions.sessionsKey)
        }

        private func storedSessions() -> [TopShelfStoredSession] {
            TopShelfSessions.decode(
                v2: defaults?.data(forKey: TopShelfSessions.sessionsKey),
                v1: defaults?.data(forKey: TopShelfSessions.legacySessionKey),
            ).sessions
        }

        private func removeLegacyEntries(keychain: Keychain) {
            try? keychain.deleteValue(forKey: TopShelfSessions.legacyTokenKey)
            try? keychain.deleteValue(forKey: TopShelfSessions.legacyPlexTokenKey)
            defaults?.removeObject(forKey: TopShelfSessions.legacySessionKey)
            defaults?.removeObject(forKey: TopShelfSessions.legacyPlexURLKey)
        }
    }
#endif
