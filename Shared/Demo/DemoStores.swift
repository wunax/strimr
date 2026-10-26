#if DEBUG
    import Foundation

    /// Account, profile and settings stores seeded with the demo server, kept apart from the real ones so a demo
    /// launch never touches the Keychain or the user's preferences.
    @MainActor
    struct DemoStores {
        let defaults: UserDefaults
        let accountStore: AccountStore
        let profileStore: ProfileStore

        static func makeIfEnabled() -> DemoStores? {
            guard DemoMode.isEnabled else { return nil }
            let suiteName = "strimr.demo"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)

            let accountStore = AccountStore(userDefaults: defaults, secureStore: DemoSecureStore())
            let account = MediaAccount.jellyfin(JellyfinAccount(connection: JellyfinConnection(
                baseURL: URL(string: "https://demo.invalid")!,
                serverID: DemoMode.server.id,
                serverName: "Strimr Demo",
                serverVersion: "10.11.0",
                userID: DemoMode.userID,
                username: "Demo",
            )))
            try? accountStore.save(account, token: "demo")

            let profile = LocalProfile(id: "local.demo", name: "Demo")
            var state = ProfileStore.State()
            state.localProfiles = [profile]
            state.links = [ProfileLink(
                profileID: profile.id,
                accountID: account.id,
                user: .jellyfin(userID: DemoMode.userID),
            )]
            state.activeProfileID = profile.id
            let profileStore = ProfileStore(userDefaults: defaults)
            profileStore.replaceState(state)

            return DemoStores(defaults: defaults, accountStore: accountStore, profileStore: profileStore)
        }
    }

    private final class DemoSecureStore: SecureStore {
        private var values: [String: String] = [:]

        func string(forKey key: String) throws -> String? {
            values[key]
        }

        func setString(_ value: String, forKey key: String) throws {
            values[key] = value
        }

        func deleteValue(forKey key: String) throws {
            values[key] = nil
        }
    }
#endif
