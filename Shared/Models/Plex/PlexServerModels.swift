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

/// Images listed by `/library/metadata/{id}/posters`, `arts` or `clearLogos`.
nonisolated struct PlexArtworkResponse: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let metadata: [PlexArtwork]?

        private enum CodingKeys: String, CodingKey {
            case metadata = "Metadata"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

nonisolated struct PlexArtwork: Codable, Equatable {
    /// URL of the full-size image, or a path on the server for a local or uploaded one.
    let key: String
    /// What Plex expects to select the image: the URL of a remote one, or the `metadata://`, `media://` or
    /// `upload://` reference of one stored on the server, whose `key` only serves the file.
    let ratingKey: PlexLenient<String>?
    let thumb: String?
    /// Absent for a local or uploaded image.
    let provider: String?
    let selected: PlexLenient<Bool>?
}
