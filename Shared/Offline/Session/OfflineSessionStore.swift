import Foundation

/// Snapshot of the last working Plex session so the app can start without plex.tv. The user is stored without its
/// token and the selected resource (which carries the server access token) lives in the Keychain.
struct OfflineSessionStore {
    struct PlexSnapshot {
        let user: PlexCloudUser
        let resource: PlexCloudResource
    }

    private let keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    private let userDefaultsKey = "strimr.offline.session.plex.user.v1"
    private let resourceKeychainKey = "strimr.offline.session.plex.resource.v1"

    func savePlex(user: PlexCloudUser, resource: PlexCloudResource) {
        let sanitizedUser = PlexCloudUser(
            id: user.id,
            uuid: user.uuid,
            username: user.username,
            title: user.title,
            friendlyName: user.friendlyName,
            authToken: "",
            thumb: user.thumb,
        )
        do {
            let userData = try JSONEncoder().encode(sanitizedUser)
            let resourceData = try JSONEncoder().encode(resource)
            try keychain.setString(String(decoding: resourceData, as: UTF8.self), forKey: resourceKeychainKey)
            UserDefaults.standard.set(userData, forKey: userDefaultsKey)
        } catch {
            ErrorReporter.capture(error)
        }
    }

    func loadPlex(token: String) -> PlexSnapshot? {
        guard let userData = UserDefaults.standard.data(forKey: userDefaultsKey),
              let stored = try? JSONDecoder().decode(PlexCloudUser.self, from: userData),
              let resourceString = try? keychain.string(forKey: resourceKeychainKey),
              let resource = try? JSONDecoder().decode(PlexCloudResource.self, from: Data(resourceString.utf8))
        else { return nil }
        let user = PlexCloudUser(
            id: stored.id,
            uuid: stored.uuid,
            username: stored.username,
            title: stored.title,
            friendlyName: stored.friendlyName,
            authToken: token,
            thumb: stored.thumb,
        )
        return PlexSnapshot(user: user, resource: resource)
    }

    func clearPlex() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        try? keychain.deleteValue(forKey: resourceKeychainKey)
    }
}
