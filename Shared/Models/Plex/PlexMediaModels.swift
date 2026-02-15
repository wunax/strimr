import Foundation

enum PlexItemType: String, Codable {
    case movie
    case show
    case season
    case episode
    case collection
    case playlist
    case unknown

    var isSupported: Bool {
        self != .unknown
    }

    var isPlayable: Bool {
        switch self {
        case .movie, .show, .season, .episode:
            true
        case .collection, .playlist, .unknown:
            false
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = PlexItemType(rawValue: rawValue) ?? .unknown
    }
}

struct PlexHub: Codable, Equatable {
    let hubKey: String?
    let key: String
    let title: String
    let hubIdentifier: String
    let size: Int
    let metadata: [PlexItem]?

    private enum CodingKeys: String, CodingKey {
        case hubKey, key, title, hubIdentifier, size
        case metadata = "Metadata"
    }
}

struct PlexSection: Codable, Equatable {
    let agent: String
    let key: String
    let type: PlexItemType
    let title: String
}

struct PlexSectionItemMeta: Codable, Equatable {
    let type: [PlexSectionItemMetaType]

    private enum CodingKeys: String, CodingKey {
        case type = "Type"
    }
}

struct PlexSectionItemMetaType: Codable, Equatable {
    let key: String
    let type: PlexItemType
    let title: String
    let active: Bool?
    let filter: [PlexSectionItemFilter]?
    let sort: [PlexSectionItemSort]?

    private enum CodingKeys: String, CodingKey {
        case key, type, title, active
        case filter = "Filter"
        case sort = "Sort"
    }
}

struct PlexSectionItemFilter: Codable, Equatable {
    let filter: String
    let filterType: String
    let key: String
    let title: String
    let type: String

    var isBoolean: Bool {
        filterType.lowercased() == "boolean"
    }
}

enum PlexSortDirection: String, Codable {
    case asc
    case desc

    var opposite: PlexSortDirection {
        switch self {
        case .asc:
            .desc
        case .desc:
            .asc
        }
    }
}

struct PlexSectionItemSort: Codable, Equatable {
    let active: Bool?
    let activeDirection: PlexSortDirection?
    let defaultDirection: PlexSortDirection
    let defaultValue: PlexSortDirection?
    let descKey: String
    let key: String
    let title: String

    private enum CodingKeys: String, CodingKey {
        case active
        case activeDirection
        case defaultDirection
        case defaultValue = "default"
        case descKey
        case key
        case title
    }
}

struct PlexTag: Codable, Equatable {
    let tag: String
}

struct PlexTagPerson: Codable, Equatable {
    let id: Int?
    let tag: String
    let role: String?
    let thumb: String?
}

struct PlexImage: Codable, Equatable {
    let alt: String
    let type: String
    let url: URL
}

struct PlexGuid: Codable, Equatable {
    let id: String
}

struct PlexUltraBlurColors: Codable, Equatable, Hashable {
    let topLeft: String
    let topRight: String
    let bottomRight: String
    let bottomLeft: String
}

struct PlexMarkerAttributes: Codable, Equatable {
    let id: Int
    let version: Int?
}

enum PlexMarkerType: String, Codable {
    case intro
    case credits
}

struct PlexMarker: Codable, Equatable {
    let id: Int
    let type: PlexMarkerType
    let startTimeOffset: Int
    let endTimeOffset: Int
    let isFinal: Bool?
    let attributes: PlexMarkerAttributes?

    var startTime: Double {
        Double(startTimeOffset) / 1000
    }

    var endTime: Double {
        Double(endTimeOffset) / 1000
    }

    var isIntro: Bool {
        if case .intro = type { return true }
        return false
    }

    var isCredits: Bool {
        if case .credits = type { return true }
        return false
    }

    func contains(time: Double) -> Bool {
        time >= startTime && time <= endTime
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, startTimeOffset, endTimeOffset
        case attributes = "Attributes"
        case isFinal = "final"
    }
}

struct PlexPartStream: Codable, Equatable, Hashable {
    enum PlexPartStreamType: Int, Codable, Equatable {
        case video = 1
        case audio = 2
        case subtitle = 3
    }

    let id: Int
    let index: Int?
    let codec: String
    let streamType: PlexPartStreamType
    let selected: Bool?
    let title: String?
    let displayTitle: String
}

struct PlexPart: Codable, Equatable {
    let id: Int
    let key: String
    let stream: [PlexPartStream]?

    private enum CodingKeys: String, CodingKey {
        case id, key
        case stream = "Stream"
    }
}

struct PlexMedia: Codable, Equatable {
    let id: Int
    let videoResolution: String?
    let parts: [PlexPart]

    private enum CodingKeys: String, CodingKey {
        case id, videoResolution
        case parts = "Part"
    }
}

struct PlexItem: Codable, Equatable {
    // Base fields
    let ratingKey: String
    let key: String
    let guid: String
    let type: PlexItemType
    let title: String
    let summary: String?
    let thumb: String?
    let art: String?
    let year: Int?
    let viewOffset: Int?
    let lastViewedAt: Int?
    let viewCount: Int?
    let originallyAvailableAt: String?
    let duration: Int?
    let audienceRating: Double?
    let audienceRatingImage: String?
    let contentRating: String?
    let contentRatingAge: Int?
    let tagline: String?
    let ultraBlurColors: PlexUltraBlurColors?
    let images: [PlexImage]?
    let guids: [PlexGuid]?
    let genres: [PlexTag]?
    let countries: [PlexTag]?
    let directors: [PlexTagPerson]?
    let writers: [PlexTagPerson]?
    let roles: [PlexTagPerson]?
    let media: [PlexMedia]?
    let markers: [PlexMarker]?

    // Movie
    let slug: String?
    let studio: String?
    let rating: Double?
    let chapterSource: String?
    let primaryExtraKey: String?
    let ratingImage: String?

    // Show
    let index: Int?
    let leafCount: Int?
    let viewedLeafCount: Int?
    let childCount: Int?

    // Season
    let parentRatingKey: String?
    let parentGuid: String?
    let parentSlug: String?
    let parentStudio: String?
    let parentKey: String?
    let parentTitle: String?
    let parentThumb: String?
    let parentYear: Int?
    let parentIndex: Int?

    // Episode
    let grandparentRatingKey: String?
    let grandparentGuid: String?
    let grandparentSlug: String?
    let titleSort: String?
    let grandparentKey: String?
    let grandparentTitle: String?
    let originalTitle: String?
    let grandparentThumb: String?
    let grandparentArt: String?

    let onDeck: PlexOnDeck?

    /// Queue item
    let playQueueItemID: Int?

    // Collection
    let subtype: PlexItemType?
    let minYear: String?
    let maxYear: String?

    // Playlist
    let composite: String?
    let playlistType: String?
    let smart: Bool?

    private enum CodingKeys: String, CodingKey {
        case ratingKey, key, guid, type, title, summary, thumb, art, year, viewOffset, lastViewedAt, viewCount
        case originallyAvailableAt, duration, audienceRating, audienceRatingImage, contentRating
        case contentRatingAge, tagline, slug, studio, rating, chapterSource, primaryExtraKey, ratingImage
        case index, leafCount, viewedLeafCount, childCount
        case parentRatingKey, parentGuid, parentSlug, parentStudio, parentKey, parentTitle, parentThumb, parentYear
        case parentIndex
        case grandparentRatingKey, grandparentGuid, grandparentSlug, titleSort, grandparentKey, grandparentTitle
        case originalTitle, grandparentThumb, grandparentArt
        case ultraBlurColors = "UltraBlurColors"
        case images = "Image"
        case guids = "Guid"
        case genres = "Genre"
        case countries = "Country"
        case directors = "Director"
        case writers = "Writer"
        case roles = "Role"
        case media = "Media"
        case markers = "Marker"
        case onDeck = "OnDeck"
        case playQueueItemID
        case subtype, minYear, maxYear, composite, playlistType, smart
    }
}

struct PlexHubMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let hub: [PlexHub]?

        private enum CodingKeys: String, CodingKey {
            case size
            case hub = "Hub"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

final class PlexOnDeck: Codable, Equatable {
    let metadata: PlexItem?

    init(metadata: PlexItem?) {
        self.metadata = metadata
    }

    static func == (lhs: PlexOnDeck, rhs: PlexOnDeck) -> Bool {
        lhs.metadata == rhs.metadata
    }

    private enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
    }
}

struct PlexItemMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let totalSize: Int?
        let metadata: [PlexItem]?
        let meta: PlexSectionItemMeta?

        private enum CodingKeys: String, CodingKey {
            case size
            case totalSize
            case metadata = "Metadata"
            case meta = "Meta"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexBrowseMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let totalSize: Int?
        let metadata: [PlexBrowseMetadata]?
        let meta: PlexSectionItemMeta?

        private enum CodingKeys: String, CodingKey {
            case size
            case totalSize
            case metadata = "Metadata"
            case meta = "Meta"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

enum PlexBrowseMetadata: Codable, Equatable {
    case item(PlexItem)
    case folder(PlexFolderItem)

    init(from decoder: Decoder) throws {
        if let item = try? PlexItem(from: decoder) {
            self = .item(item)
            return
        }
        if let folder = try? PlexFolderItem(from: decoder) {
            self = .folder(folder)
            return
        }
        throw DecodingError.typeMismatch(
            PlexBrowseMetadata.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported Plex browse metadata payload.",
            ),
        )
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .item(item):
            try item.encode(to: encoder)
        case let .folder(folder):
            try folder.encode(to: encoder)
        }
    }
}

struct PlexFolderItem: Codable, Equatable {
    let key: String
    let title: String
}

struct PlexFilterMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let directory: [PlexFilterDirectory]?

        private enum CodingKeys: String, CodingKey {
            case size
            case directory = "Directory"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexFilterDirectory: Codable, Equatable {
    let fastKey: String?
    let key: String
    let title: String
    let type: String?
}

struct PlexSearchResult: Codable, Equatable {
    let score: Double?
    let metadata: PlexItem?

    private enum CodingKeys: String, CodingKey {
        case score
        case metadata = "Metadata"
    }
}

struct PlexSearchMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let searchResult: [PlexSearchResult]?

        private enum CodingKeys: String, CodingKey {
            case size
            case searchResult = "SearchResult"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexSectionMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let directory: [PlexSection]?

        private enum CodingKeys: String, CodingKey {
            case size
            case directory = "Directory"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexFirstCharacterMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let directory: [PlexFirstCharacterDirectory]?

        private enum CodingKeys: String, CodingKey {
            case size
            case directory = "Directory"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexFirstCharacterDirectory: Codable, Equatable {
    let size: Int?
    let key: String?
    let title: String?
}
