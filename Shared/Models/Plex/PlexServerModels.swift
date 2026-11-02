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

/// Titles listed by `/library/metadata/{id}/matches`.
nonisolated struct PlexMatchResponse: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let searchResult: [PlexMatchResult]?

        private enum CodingKeys: String, CodingKey {
            case searchResult = "SearchResult"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

nonisolated struct PlexMatchResult: Codable, Equatable {
    /// `plex://movie/…` with the Plex agents, `com.plexapp.agents.…://…` with the legacy ones.
    let guid: String
    let name: String
    let year: PlexLenient<String>?
    /// Absent for some titles.
    let thumb: String?
}

/// The fields of an item that the metadata editor shows, with the fields locked against refreshes.
nonisolated struct PlexEditableMetadataResponse: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let librarySectionID: PlexLenient<String>?
        let metadata: [PlexEditableMetadata]?

        private enum CodingKeys: String, CodingKey {
            case librarySectionID
            case metadata = "Metadata"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

nonisolated struct PlexEditableMetadata: Codable, Equatable {
    struct Field: Codable, Equatable {
        let name: String
        let locked: PlexLenient<Bool>?
    }

    let librarySectionID: PlexLenient<String>?
    let title: String?
    let titleSort: String?
    let originalTitle: String?
    let originallyAvailableAt: String?
    let contentRating: String?
    let studio: String?
    let tagline: String?
    let summary: String?
    let genres: [PlexTag]?
    let labels: [PlexTag]?
    let directors: [PlexTag]?
    let writers: [PlexTag]?
    let countries: [PlexTag]?
    let fields: [Field]?

    private enum CodingKeys: String, CodingKey {
        case librarySectionID, title, titleSort, originalTitle, originallyAvailableAt, contentRating, studio, tagline
        case summary
        case genres = "Genre"
        case labels = "Label"
        case directors = "Director"
        case writers = "Writer"
        case countries = "Country"
        case fields = "Field"
    }
}

/// The values of a tag across a library section, such as its genres.
nonisolated struct PlexTagValuesResponse: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let directory: [Directory]?

        private enum CodingKeys: String, CodingKey {
            case directory = "Directory"
        }
    }

    struct Directory: Codable, Equatable {
        let title: String
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}
