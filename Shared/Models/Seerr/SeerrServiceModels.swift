import Foundation

struct SeerrServiceProfile: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String?
}

struct SeerrServiceRootFolder: Identifiable, Hashable, Decodable {
    let id: Int
    let freeSpace: Int?
    let path: String?
}

struct SeerrServiceTag: Identifiable, Hashable, Decodable {
    let id: Int
    let label: String?
}

struct SeerrSonarrServer: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String?
    let is4k: Bool?
    let isDefault: Bool?
    let activeDirectory: String?
    let activeProfileId: Int?
    let activeAnimeProfileId: Int?
    let activeAnimeDirectory: String?
    let activeTags: [Int]?
    let activeAnimeTags: [Int]?
}

struct SeerrRadarrServer: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String?
    let is4k: Bool?
    let isDefault: Bool?
    let activeDirectory: String?
    let activeProfileId: Int?
    let activeTags: [Int]?
}

struct SeerrSonarrServiceDetail: Hashable, Decodable {
    let server: SeerrSonarrServer
    let profiles: [SeerrServiceProfile]
    let rootFolders: [SeerrServiceRootFolder]
    let tags: [SeerrServiceTag]
}

struct SeerrRadarrServiceDetail: Hashable, Decodable {
    let server: SeerrRadarrServer
    let profiles: [SeerrServiceProfile]
    let rootFolders: [SeerrServiceRootFolder]
    let tags: [SeerrServiceTag]
}
