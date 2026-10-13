import Foundation

nonisolated struct PlexDiscoverUserStateResponse: Codable, Equatable {
    let mediaContainer: PlexDiscoverUserStateContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

nonisolated struct PlexDiscoverUserStateContainer: Codable, Equatable {
    let identifier: String?
    let size: Int?
    let userState: [PlexDiscoverUserState]?

    private enum CodingKeys: String, CodingKey {
        case identifier
        case size
        case userState = "UserState"
    }
}

nonisolated struct PlexDiscoverUserState: Codable, Equatable {
    let ratingKey: String
    let type: String
    let viewCount: Int?
    let viewOffset: Int?
    let watchlistedAt: Int?
}
