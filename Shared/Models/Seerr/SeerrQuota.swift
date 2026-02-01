import Foundation

struct SeerrUserQuota: Hashable, Decodable {
    let movie: SeerrQuotaRestriction
    let tv: SeerrQuotaRestriction
}

struct SeerrQuotaRestriction: Hashable, Decodable {
    let days: Int?
    let limit: Int?
    let used: Int?
    let remaining: Int?
    let restricted: Bool
}
