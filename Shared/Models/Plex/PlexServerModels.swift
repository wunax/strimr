import Foundation

nonisolated struct PlexServerRootResponse: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        /// The server's "Allow media deletion" setting.
        let allowMediaDeletion: Bool?
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

enum PlexServerRights {
    /// The server must belong to the account, and the profile be the Home's admin unless there is no Plex Home.
    static func isAdministrator(
        resourceOwned: Bool?,
        homeUsers: [PlexHomeUser],
        userUUID: String,
        accountID: String,
    ) -> Bool {
        guard resourceOwned == true else { return false }
        if let user = homeUsers.first(where: { $0.uuid == userUUID }) {
            return user.admin == true
        }
        return homeUsers.isEmpty || userUUID == accountID
    }
}
