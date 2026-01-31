import Foundation

enum SeerrMediaRequestStatus: Int, Hashable, Decodable {
    case pending = 1
    case approved = 2
    case declined = 3
    case failed = 4
    case completed = 5
}

struct SeerrRequest: Identifiable, Hashable, Decodable {
    let id: Int
    let is4k: Bool?
    let status: SeerrMediaRequestStatus?
    let requestedBy: SeerrUser?
    let seasons: [SeerrRequestSeasonInfo]?
}

struct SeerrRequestSeasonInfo: Identifiable, Hashable, Decodable {
    let id: Int
    let seasonNumber: Int?
    let status: SeerrMediaRequestStatus?
}
