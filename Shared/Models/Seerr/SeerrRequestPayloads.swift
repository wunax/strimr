import Foundation

struct SeerrMediaRequestPayload: Encodable {
    let mediaId: Int
    let mediaType: SeerrMediaType
    let is4k: Bool
    let tvdbId: Int?
    let seasons: [Int]?
    let serverId: Int?
    let profileId: Int?
    let rootFolder: String?
    let tags: [Int]?
}
