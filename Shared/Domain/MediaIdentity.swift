import Foundation

enum MediaProvider: String, Codable, Hashable, Sendable {
    case plex
    case jellyfin
}

struct ServerIdentity: Codable, Hashable, Sendable {
    let provider: MediaProvider
    let id: String

    /// Stable `<provider>:<serverID>` form used in persisted keys.
    var stableKey: String {
        "\(provider.rawValue):\(id)"
    }

    init(provider: MediaProvider, id: String) {
        self.provider = provider
        self.id = id
    }

    init?(stableKey: String) {
        let parts = stableKey.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let provider = MediaProvider(rawValue: String(parts[0])), !parts[1].isEmpty
        else { return nil }
        self.init(provider: provider, id: String(parts[1]))
    }
}

extension ServerIdentity {
    /// Placeholder for values decoded from data persisted before they carried their server. Stores that know the
    /// server re-assign it after decoding.
    static let unassigned = ServerIdentity(provider: .plex, id: "")
}

struct LibraryIdentity: Hashable, Sendable {
    let server: ServerIdentity
    let libraryID: String

    /// Stable `<provider>:<serverID>:<libraryID>` form used in `UserDefaults` and fixtures.
    var stableKey: String {
        "\(server.stableKey):\(libraryID)"
    }

    init(server: ServerIdentity, libraryID: String) {
        self.server = server
        self.libraryID = libraryID
    }

    init?(stableKey: String) {
        let parts = stableKey.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let provider = MediaProvider(rawValue: String(parts[0])),
              !parts[1].isEmpty,
              !parts[2].isEmpty
        else { return nil }
        self.init(server: ServerIdentity(provider: provider, id: String(parts[1])), libraryID: String(parts[2]))
    }
}

extension LibraryIdentity: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let identity = LibraryIdentity(stableKey: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid library identity")
        }
        self = identity
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stableKey)
    }
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
    case clip
    case collection
    case playlist
    case folder
    case unknown

    var isSupported: Bool {
        self != .unknown && self != .folder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = value == "show" ? .series : MediaKind(rawValue: value) ?? .unknown
    }
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

    static let jellyfin = ProviderCapabilities(
        profiles: false,
        multiServerSearch: false,
        cloudWatchlist: false,
        favorites: true,
        remoteSubtitleSearch: true,
        trickplay: true,
        skipSegments: true,
        downloads: true,
        sharePlay: true,
        topShelf: true,
        syncPlay: false,
    )

    static let plex = ProviderCapabilities(
        profiles: true,
        multiServerSearch: true,
        cloudWatchlist: true,
        favorites: true,
        remoteSubtitleSearch: true,
        trickplay: true,
        skipSegments: true,
        downloads: true,
        sharePlay: true,
        topShelf: true,
        syncPlay: false,
    )
}
