import Foundation
import Observation

/// Accounts and their secrets: plex.tv tokens, Jellyfin tokens, Plex Home tokens and the Plex resources cached for
/// offline starts.
@MainActor
@Observable
final class AccountStore {
    private(set) var accounts: [MediaAccount]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let secureStore: any SecureStore

    static let storageKey = "strimr.accounts.v1"

    init(
        userDefaults: UserDefaults = .standard,
        secureStore: any SecureStore = Keychain(service: Bundle.main.bundleIdentifier!),
    ) {
        defaults = userDefaults
        self.secureStore = secureStore
        if let data = userDefaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([MediaAccount].self, from: data)
        {
            accounts = stored
        } else {
            accounts = []
        }
    }

    func account(id: String) -> MediaAccount? {
        accounts.first { $0.id == id }
    }

    var plexAccounts: [PlexAccount] {
        accounts.compactMap(\.plexAccount)
    }

    var jellyfinAccounts: [JellyfinAccount] {
        accounts.compactMap(\.jellyfinAccount)
    }

    // MARK: - Accounts

    /// Adds or replaces the account and stores its token. The token is written first so an account is never listed
    /// without one.
    func save(_ account: MediaAccount, token: String) throws {
        try secureStore.setString(token, forKey: Self.tokenKey(for: account))
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        try persist()
    }

    func remove(accountID: String) throws {
        guard let account = account(id: accountID) else { return }
        accounts.removeAll { $0.id == accountID }
        try persist()
        try? secureStore.deleteValue(forKey: Self.tokenKey(for: account))
    }

    func token(for account: MediaAccount) throws -> String? {
        try secureStore.string(forKey: Self.tokenKey(for: account))
    }

    func token(forAccountID accountID: String) throws -> String? {
        guard let account = account(id: accountID) else { return nil }
        return try token(for: account)
    }

    // MARK: - Plex Home

    func homeToken(accountID: String, userUUID: String) -> String? {
        try? secureStore.string(forKey: Self.homeTokenKey(accountID: accountID, userUUID: userUUID))
    }

    func setHomeToken(_ token: String, accountID: String, userUUID: String) {
        do {
            try secureStore.setString(token, forKey: Self.homeTokenKey(accountID: accountID, userUUID: userUUID))
        } catch {
            ErrorReporter.capture(error)
        }
    }

    func removeHomeToken(accountID: String, userUUID: String) {
        try? secureStore.deleteValue(forKey: Self.homeTokenKey(accountID: accountID, userUUID: userUUID))
    }

    // MARK: - Plex resources

    /// Last resources returned to a Plex user. They carry server tokens, hence the secure store.
    func cachedResources(userUUID: String) -> [PlexCloudResource]? {
        guard let value = try? secureStore.string(forKey: Self.resourcesKey(userUUID: userUUID)) else { return nil }
        return try? JSONDecoder().decode([PlexCloudResource].self, from: Data(value.utf8))
    }

    func setCachedResources(_ resources: [PlexCloudResource], userUUID: String) {
        do {
            let data = try JSONEncoder().encode(resources)
            try secureStore.setString(
                String(decoding: data, as: UTF8.self),
                forKey: Self.resourcesKey(userUUID: userUUID),
            )
        } catch {
            ErrorReporter.capture(error)
        }
    }

    func removeCachedResources(userUUID: String) {
        try? secureStore.deleteValue(forKey: Self.resourcesKey(userUUID: userUUID))
    }

    // MARK: - Keys

    static func tokenKey(for account: MediaAccount) -> String {
        switch account {
        case let .plex(account):
            "strimr.plex.account.\(account.id)"
        case let .jellyfin(account):
            jellyfinTokenKey(serverID: account.connection.serverID, userID: account.connection.userID)
        }
    }

    static func jellyfinTokenKey(serverID: String, userID: String) -> String {
        "strimr.jellyfin.token.\(serverID).\(userID)"
    }

    static func homeTokenKey(accountID: String, userUUID: String) -> String {
        "strimr.plex.home.\(accountID).\(userUUID)"
    }

    static func resourcesKey(userUUID: String) -> String {
        "strimr.plex.resources.\(userUUID)"
    }

    private func persist() throws {
        try defaults.set(JSONEncoder().encode(accounts), forKey: Self.storageKey)
    }
}
