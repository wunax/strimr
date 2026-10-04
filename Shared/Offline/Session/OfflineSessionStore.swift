import Foundation

/// User of the last Plex session of the single-server versions, only read by the multi-server migration to know the
/// Plex user without contacting plex.tv. It was stored without its token.
struct OfflineSessionStore {
    private let userDefaultsKey = "strimr.offline.session.plex.user.v1"

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
}
