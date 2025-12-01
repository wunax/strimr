import Foundation

enum PlexItemType: String, Codable {
    case movie
    case show
    case season
    case episode
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
}

enum PlexSortDirection: String, Codable {
    case asc
    case desc
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

struct PlexImage: Codable, Equatable {
    let alt: String
    let type: String
    let url: URL
}

struct PlexGuid: Codable, Equatable {
    let id: String
}

struct PlexUltraBlurColors: Codable, Equatable {
    let topLeft: String
    let topRight: String
    let bottomRight: String
    let bottomLeft: String
}

struct PlexPart: Codable, Equatable {
    let id: Int
    let key: String
    let duration: Int
    let file: String
    let size: Int
    let container: String
    let videoProfile: String?
}

struct PlexMedia: Codable, Equatable {
    let id: Int
    let duration: Int
    let bitrate: Int
    let width: Int
    let height: Int
    let aspectRatio: Double
    let audioChannels: Int
    let audioCodec: String
    let videoCodec: String
    let videoResolution: String
    let container: String
    let videoFrameRate: String
    let videoProfile: String
    let hasVoiceActivity: Bool
    let parts: [PlexPart]

    private enum CodingKeys: String, CodingKey {
        case id, duration, bitrate, width, height, aspectRatio, audioChannels, audioCodec, videoCodec, videoResolution
        case container, videoFrameRate, videoProfile, hasVoiceActivity
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
    let addedAt: Int
    let updatedAt: Int
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
    let directors: [PlexTag]?
    let writers: [PlexTag]?
    let roles: [PlexTag]?
    let media: [PlexMedia]?

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

    private enum CodingKeys: String, CodingKey {
        case ratingKey, key, guid, type, title, summary, thumb, art, year, viewOffset, lastViewedAt, viewCount
        case originallyAvailableAt, addedAt, updatedAt, duration, audienceRating, audienceRatingImage, contentRating
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
    }
}

struct PlexHubMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let hub: [PlexHub]

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

struct PlexItemMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let totalSize: Int?
        let metadata: [PlexItem]?

        private enum CodingKeys: String, CodingKey {
            case size
            case totalSize
            case metadata = "Metadata"
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

struct PlexSectionMetaMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let meta: PlexSectionItemMeta?

        private enum CodingKeys: String, CodingKey {
            case size
            case meta = "Meta"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexDirectoryMediaContainer: Codable, Equatable {
    struct MediaContainer: Codable, Equatable {
        let size: Int?
        let directory: [PlexItem]?

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
