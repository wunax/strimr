import Foundation

#if os(tvOS)
    struct TopShelfSessionStore {
        private static let appGroup = "group.com.github.wunax.strimr"
        private static let keychainService = "com.github.wunax.strimr.top-shelf"
        private static let tokenKey = "media.serverToken"
        private static let sessionKey = "media.session.v1"
        // Kept for upgrades from the Plex-only format; remove after a future migration window.
        private static let legacyTokenKey = "plex.serverToken"
        private static let legacyURLKey = "plex.serverURL"

        private struct StoredSession: Codable {
            let provider: MediaProvider
            let serverURL: URL
            let serverID: String
            let userID: String?
        }

        private let defaults = UserDefaults(suiteName: appGroup)

        func save(
            provider: MediaProvider,
            serverURL: URL,
            serverID: String,
            userID: String?,
            token: String
        ) throws {
            guard let accessGroup = Bundle.main.object(forInfoDictionaryKey: "TopShelfKeychainAccessGroup") as? String,
                  !accessGroup.isEmpty
            else {
                return
            }

            let keychain = Keychain(service: Self.keychainService, accessGroup: accessGroup)
            try keychain.setString(token, forKey: Self.tokenKey)
            try? keychain.deleteValue(forKey: Self.legacyTokenKey)
            defaults?.set(
                try JSONEncoder().encode(StoredSession(
                    provider: provider,
                    serverURL: serverURL,
                    serverID: serverID,
                    userID: userID
                )),
                forKey: Self.sessionKey
            )
            defaults?.removeObject(forKey: Self.legacyURLKey)
        }

        func clear() {
            if let accessGroup = Bundle.main.object(forInfoDictionaryKey: "TopShelfKeychainAccessGroup") as? String {
                try? Keychain(service: Self.keychainService, accessGroup: accessGroup)
                    .deleteValue(forKey: Self.tokenKey)
                try? Keychain(service: Self.keychainService, accessGroup: accessGroup)
                    .deleteValue(forKey: Self.legacyTokenKey)
            }
            defaults?.removeObject(forKey: Self.sessionKey)
            defaults?.removeObject(forKey: Self.legacyURLKey)
        }
    }
#endif
