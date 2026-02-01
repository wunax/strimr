import Foundation

struct SeerrRequestCount: Hashable, Decodable {
    let total: Int
    let movie: Int
    let tv: Int
    let pending: Int
    let approved: Int
    let declined: Int
    let processing: Int
    let available: Int
}
