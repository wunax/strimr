import Foundation

struct SeerrPaginatedResponse<Item: Decodable>: Decodable {
    let page: Int
    let totalPages: Int
    let totalResults: Int
    let results: [Item]

    private enum CodingKeys: String, CodingKey {
        case page
        case totalPages
        case totalResults
        case results
    }
}
