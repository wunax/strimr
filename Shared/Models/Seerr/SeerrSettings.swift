import Foundation

struct SeerrSettings: Hashable, Decodable {
    let movie4kEnabled: Bool
    let series4kEnabled: Bool
    let partialRequestsEnabled: Bool
    let enableSpecialEpisodes: Bool
}
