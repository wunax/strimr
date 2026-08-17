import Foundation

struct MediaHierarchy: Hashable, Sendable {
    var parentID: MediaIdentity?
    var seriesID: MediaIdentity?
    var seasonID: MediaIdentity?
    var seriesTitle: String?
    var seasonTitle: String?
    var seasonNumber: Int?
    var episodeNumber: Int?

    static let empty = MediaHierarchy()
}

struct MediaWatchState: Hashable, Sendable {
    var isPlayed: Bool
    var playCount: Int
    var resumePosition: TimeInterval?
    var unplayedItemCount: Int?
    var isFavorite: Bool

    static let empty = MediaWatchState(
        isPlayed: false,
        playCount: 0,
        resumePosition: nil,
        unplayedItemCount: nil,
        isFavorite: false,
    )
}

struct MediaCounts: Hashable, Sendable {
    var childCount: Int?
    var leafCount: Int?
    var viewedLeafCount: Int?

    static let empty = MediaCounts()
}

enum ArtworkKind: String, Codable, Hashable, Sendable {
    case poster
    case backdrop
    case thumbnail
    case logo
}

struct ArtworkReference: Hashable, Sendable {
    let owner: MediaIdentity
    let kind: ArtworkKind
    let index: Int?
    let tag: String?
    let opaquePath: String?
}

struct MediaArtwork: Hashable, Sendable {
    var poster: ArtworkReference?
    var backdrop: ArtworkReference?
    var thumbnail: ArtworkReference?
    var logo: ArtworkReference?

    static let empty = MediaArtwork()
}

struct MediaPage<Element: Sendable>: Sendable {
    let items: [Element]
    let startIndex: Int
    let totalCount: Int?
}

extension MediaKind {
    var isPlayable: Bool {
        self == .movie || self == .series || self == .season || self == .episode
    }
}
