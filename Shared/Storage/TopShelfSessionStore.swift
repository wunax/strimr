import Foundation

#if os(tvOS)
    struct TopShelfSessionStore {
        private static let appGroup = "group.com.github.wunax.strimr"
        private static let keychainService = "com.github.wunax.strimr.top-shelf"
        private static let tokenKey = "plex.serverToken"
        private static let serverURLKey = "plex.serverURL"

        private let defaults = UserDefaults(suiteName: appGroup)

        func save(serverURL: URL, token: String) throws {
            guard let accessGroup = Bundle.main.object(forInfoDictionaryKey: "TopShelfKeychainAccessGroup") as? String,
                  !accessGroup.isEmpty
            else {
                return
            }

            let keychain = Keychain(service: Self.keychainService, accessGroup: accessGroup)
            try keychain.setString(token, forKey: Self.tokenKey)
            defaults?.set(serverURL.absoluteString, forKey: Self.serverURLKey)
        }

        func clear() {
            if let accessGroup = Bundle.main.object(forInfoDictionaryKey: "TopShelfKeychainAccessGroup") as? String {
                try? Keychain(service: Self.keychainService, accessGroup: accessGroup)
                    .deleteValue(forKey: Self.tokenKey)
            }
            defaults?.removeObject(forKey: Self.serverURLKey)
        }
    }
#endif
