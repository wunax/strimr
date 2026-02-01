import Foundation

struct SeerrRequestPageInfo: Hashable, Decodable {
    let page: Int
    let pages: Int
    let results: Int
}

struct SeerrRequestPageResponse: Hashable, Decodable {
    let pageInfo: SeerrRequestPageInfo
    let results: [SeerrRequest]
}
