import Foundation

struct SeerrUser: Identifiable, Hashable, Decodable {
    let id: Int
    let permissions: Int?
    let displayName: String?
    let avatar: String?
}
