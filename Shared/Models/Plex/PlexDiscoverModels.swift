import Foundation

/// The `MediaContainer` of Discover lists, hubs, searches and metadata.
nonisolated struct PlexDiscoverContainerResponse: Decodable {
    let mediaContainer: PlexDiscoverContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

nonisolated struct PlexDiscoverContainer: Decodable {
    let size: Int?
    let totalSize: Int?
    let metadata: [PlexDiscoverMetadata]
    let hubs: [PlexDiscoverHub]
    let searchResults: [PlexDiscoverSearchResults]

    private enum CodingKeys: String, CodingKey {
        case size
        case totalSize
        case metadata = "Metadata"
        case hubs = "Hub"
        case searchResults = "SearchResults"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try? container.decodeIfPresent(Int.self, forKey: .size)
        totalSize = try? container.decodeIfPresent(Int.self, forKey: .totalSize)
        metadata = (try? container.decodeIfPresent([PlexDiscoverMetadata].self, forKey: .metadata)) ?? []
        hubs = (try? container.decodeIfPresent([PlexDiscoverHub].self, forKey: .hubs)) ?? []
        searchResults = (try? container.decodeIfPresent([PlexDiscoverSearchResults].self, forKey: .searchResults))
            ?? []
    }
}

nonisolated struct PlexDiscoverHub: Decodable {
    let hubIdentifier: String?
    let key: String?
    let hubKey: String?
    let title: String?
    let type: String?
    let style: String?
    let metadata: [PlexDiscoverMetadata]

    private enum CodingKeys: String, CodingKey {
        case hubIdentifier
        case key
        case hubKey
        case title
        case type
        case style
        case metadata = "Metadata"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hubIdentifier = try? container.decodeIfPresent(String.self, forKey: .hubIdentifier)
        key = try? container.decodeIfPresent(String.self, forKey: .key)
        hubKey = try? container.decodeIfPresent(String.self, forKey: .hubKey)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        style = try? container.decodeIfPresent(String.self, forKey: .style)
        metadata = (try? container.decodeIfPresent([PlexDiscoverMetadata].self, forKey: .metadata)) ?? []
    }
}

nonisolated struct PlexDiscoverSearchResults: Decodable {
    let results: [PlexDiscoverSearchResult]

    private enum CodingKeys: String, CodingKey {
        case results = "SearchResult"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = (try? container.decodeIfPresent([PlexDiscoverSearchResult].self, forKey: .results)) ?? []
    }
}

nonisolated struct PlexDiscoverSearchResult: Decodable {
    let metadata: PlexDiscoverMetadata?

    private enum CodingKeys: String, CodingKey {
        case metadata = "Metadata"
    }

    /// Discover sends the result's metadata as an object or as a one-element array.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let single = try? container.decode(PlexDiscoverMetadata.self, forKey: .metadata) {
            metadata = single
        } else {
            metadata = (try? container.decode([PlexDiscoverMetadata].self, forKey: .metadata))?.first
        }
    }
}

nonisolated struct PlexDiscoverMetadata: Decodable {
    struct Guid: Decodable {
        let id: String
    }

    let ratingKey: String?
    let guid: String?
    let type: String?
    let title: String?
    let originalTitle: String?
    let year: Int?
    let summary: String?
    let thumb: String?
    let art: String?
    let guids: [Guid]

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case guid
        case type
        case title
        case originalTitle
        case year
        case summary
        case thumb
        case art
        case guids = "Guid"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = try? container.decodeIfPresent(String.self, forKey: .ratingKey)
        guid = try? container.decodeIfPresent(String.self, forKey: .guid)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        originalTitle = try? container.decodeIfPresent(String.self, forKey: .originalTitle)
        year = try? container.decodeIfPresent(Int.self, forKey: .year)
        summary = try? container.decodeIfPresent(String.self, forKey: .summary)
        thumb = try? container.decodeIfPresent(String.self, forKey: .thumb)
        art = try? container.decodeIfPresent(String.self, forKey: .art)
        guids = (try? container.decodeIfPresent([Guid].self, forKey: .guids)) ?? []
    }
}
