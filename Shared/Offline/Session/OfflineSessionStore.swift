import Foundation

/// Last Plex session of the single-server versions, only read by the multi-server migration: the user tells who the
/// Plex account is without contacting plex.tv, and the resource lets the server start offline right after the update.
struct OfflineSessionStore {
    private let keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    private let userDefaultsKey = "strimr.offline.session.plex.user.v1"
    private let resourceKeychainKey = "strimr.offline.session.plex.resource.v1"

    /// The user was stored without its token.
    func loadPlexUser(token: String) -> PlexCloudUser? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let stored = try? JSONDecoder().decode(PlexCloudUser.self, from: data)
        else { return nil }
        return PlexCloudUser(
            id: stored.id,
            uuid: stored.uuid,
            username: stored.username,
            title: stored.title,
            friendlyName: stored.friendlyName,
            authToken: token,
            thumb: stored.thumb,
        )
    }

    func loadPlexResource() -> PlexCloudResource? {
        guard let value = try? keychain.string(forKey: resourceKeychainKey) else { return nil }
        return try? JSONDecoder().decode(PlexCloudResource.self, from: Data(value.utf8))
    }
}
