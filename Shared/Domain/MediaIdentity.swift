import Foundation

enum MediaProvider: String, Codable, Hashable, Sendable {
    case plex
    case jellyfin
}

struct ServerIdentity: Codable, Hashable, Sendable {
    let provider: MediaProvider
    let id: String
}

struct MediaIdentity: Codable, Hashable, Sendable {
    let server: ServerIdentity
    let itemID: String
}

enum MediaKind: String, Codable, Hashable, Sendable {
    case movie
    case series
    case season
    case episode
    case collection
    case playlist
    case folder
    case unknown
}

struct ProviderCapabilities: Codable, Equatable, Sendable {
    let profiles: Bool
    let multiServerSearch: Bool
    let cloudWatchlist: Bool
    let favorites: Bool
    let remoteSubtitleSearch: Bool
    let trickplay: Bool
    let skipSegments: Bool
    let downloads: Bool
    let sharePlay: Bool
    let topShelf: Bool
    let syncPlay: Bool

    static let jellyfinMVP = ProviderCapabilities(
        profiles: false,
        multiServerSearch: false,
        cloudWatchlist: false,
        favorites: false,
        remoteSubtitleSearch: false,
        trickplay: false,
        skipSegments: false,
        downloads: false,
        sharePlay: false,
        topShelf: false,
        syncPlay: false,
    )

    static let plex = ProviderCapabilities(
        profiles: true,
        multiServerSearch: true,
        cloudWatchlist: true,
        favorites: false,
        remoteSubtitleSearch: true,
        trickplay: true,
        skipSegments: true,
        downloads: true,
        sharePlay: true,
        topShelf: true,
        syncPlay: false
    )
}
