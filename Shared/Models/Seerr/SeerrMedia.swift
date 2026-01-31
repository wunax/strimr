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
