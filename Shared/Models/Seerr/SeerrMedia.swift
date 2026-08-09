import Foundation

enum SeerrMediaType: String, Hashable, Codable {
    case movie
    case tv
    case person
}

struct SeerrMedia: Identifiable, Hashable, Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    var mediaType: SeerrMediaType?
    let mediaInfo: SeerrMediaInfo?
    let backdropPath: String?
    let posterPath: String?
    let profilePath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let budget: Int?
    let revenue: Int?
    let genres: [SeerrGenre]?
    let popularity: Double?
    let productionCompanies: [SeerrrProductionCompany]?
    let productionCountries: [SeerrProductionCountry]?
    let voteAverage: Double?
    let voteCount: Int?
    let runtime: Int?
    let keywords: [SeerrKeyword]?
    let credits: SeerrCredits?
    let externalIds: SeerrExternalIds?
    let tagline: String?
    let status: String?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let seasons: [SeerrSeason]?
    let createdBy: [SeerrCreatedBy]?
}

struct SeerrMediaInfo: Identifiable, Hashable, Decodable {
    let id: Int
    let status: SeerrMediaStatus?
    let status4k: SeerrMediaStatus?
    let seasons: [SeerrMediaSeasonInfo]?
    let requests: [SeerrRequest]?
    let tmdbId: Int?
    let mediaType: SeerrMediaType?
    let jellyfinMediaId: String?
    let jellyfinMediaId4k: String?

    private enum CodingKeys: String, CodingKey {
        case id, status, status4k, seasons, requests, tmdbId, mediaType
        case jellyfinMediaId, jellyfinMediaId4k
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        status = try container.decodeIfPresent(SeerrMediaStatus.self, forKey: .status)
        status4k = try container.decodeIfPresent(SeerrMediaStatus.self, forKey: .status4k)
        seasons = try container.decodeIfPresent([SeerrMediaSeasonInfo].self, forKey: .seasons)
        requests = try container.decodeIfPresent([SeerrRequest].self, forKey: .requests)
        tmdbId = try container.decodeIfPresent(Int.self, forKey: .tmdbId)
        mediaType = try container.decodeIfPresent(SeerrMediaType.self, forKey: .mediaType)
        jellyfinMediaId = Self.decodeString(container, key: .jellyfinMediaId)
        jellyfinMediaId4k = Self.decodeString(container, key: .jellyfinMediaId4k)
    }

    private static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }
}

enum SeerrMediaStatus: Int, Hashable, Decodable {
    case unknown = 1
    case pending = 2
    case processing = 3
    case partiallyAvailable = 4
    case available = 5
    case blacklisted = 6
    case deleted = 7
}

struct SeerrMediaSeasonInfo: Identifiable, Hashable, Decodable {
    let id: Int
    let seasonNumber: Int?
    let status: SeerrMediaStatus?
    let status4k: SeerrMediaStatus?
}

struct SeerrExternalIds: Hashable, Decodable {
    let tvdbId: Int?
}

struct SeerrCredits: Hashable, Decodable {
    let cast: [SeerrCastMember]?
    let crew: [SeerrCrewMember]?
}

struct SeerrGenre: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String?
}

struct SeerrrProductionCompany: Identifiable, Hashable, Decodable {
    let id: Int
    let logoPath: String?
    let name: String?
    let originCountry: String?
}

struct SeerrProductionCountry: Hashable, Decodable {
    let iso31661: String?
    let name: String?
}

struct SeerrKeyword: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String?
}

struct SeerrCastMember: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String?
    let character: String?
    let profilePath: String?
    let order: Int?
}

struct SeerrCrewMember: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String?
    let job: String?
    let department: String?
    let profilePath: String?
}

struct SeerrCreatedBy: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String?
    let profilePath: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case profilePath = "profile_path"
    }
}

struct SeerrSeason: Identifiable, Hashable, Decodable {
    let id: Int
    let seasonNumber: Int?
    let name: String?
    let overview: String?
    let airDate: String?
    let episodeCount: Int?
    let posterPath: String?
    let episodes: [SeerrEpisode]?
}

struct SeerrEpisode: Identifiable, Hashable, Decodable {
    let id: Int
    let episodeNumber: Int?
    let seasonNumber: Int?
    let name: String?
    let overview: String?
    let airDate: String?
    let stillPath: String?
    let voteAverage: Double?
    let voteCount: Int?
}
