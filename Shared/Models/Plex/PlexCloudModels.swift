import Foundation

nonisolated struct PlexCloudResource: Codable, Equatable {
    struct Connection: Codable, Equatable {
        let scheme: String
        let address: String
        let port: Int
        let uri: URL
        let isLocal: Bool
        let isRelay: Bool
        let isIPv6: Bool

        private enum CodingKeys: String, CodingKey {
            case scheme = "protocol"
            case address
            case port
            case uri
            case isLocal = "local"
            case isRelay = "relay"
            case isIPv6 = "IPv6"
        }
    }

    let name: String
    let clientIdentifier: String
    let accessToken: String?
    let connections: [Connection]?
    var owned: Bool? = nil
    var provides: String? = nil

    var isServer: Bool {
        provides.map { $0.split(separator: ",").contains("server") } ?? true
    }
}

nonisolated struct PlexCloudUser: Codable, Equatable {
    let id: Int?
    let uuid: String?
    let username: String?
    let title: String?
    let friendlyName: String?
    let authToken: String
    let thumb: String?
}

/// Reads each field on its own: this plex.tv API has returned the same field in different shapes over time.
nonisolated struct PlexAccountProfile: Decodable, Equatable {
    let defaultAudioLanguage: String?
    let autoSelectAudio: Bool?
    let defaultSubtitleLanguage: String?
    let autoSelectSubtitle: Int?

    private enum CodingKeys: String, CodingKey {
        case profile
        case defaultAudioLanguage
        case autoSelectAudio
        case defaultSubtitleLanguage
        case autoSelectSubtitle
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        let container = (try? root.nestedContainer(keyedBy: CodingKeys.self, forKey: .profile)) ?? root
        defaultAudioLanguage = Self.language(in: container, forKey: .defaultAudioLanguage)
        autoSelectAudio = Self.int(in: container, forKey: .autoSelectAudio).map { $0 != 0 }
        defaultSubtitleLanguage = Self.language(in: container, forKey: .defaultSubtitleLanguage)
        autoSelectSubtitle = Self.int(in: container, forKey: .autoSelectSubtitle)
    }

    /// A single code, a comma-separated list or an array; the first one is the preference.
    private static func language(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let values = try? container.decodeIfPresent([String].self, forKey: key) {
            return values.first
        }
        return (try? container.decodeIfPresent(String.self, forKey: key))?
            .split(separator: ",")
            .first
            .map(String.init)
    }

    private static func int(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value ? 1 : 0
        }
        return (try? container.decodeIfPresent(String.self, forKey: key)).flatMap { $0.flatMap(Int.init) }
    }
}

nonisolated struct PlexCloudPin: Codable, Equatable {
    let id: Int
    let code: String
    let clientIdentifier: String
    let authToken: String?
}

nonisolated struct PlexHome: Codable, Equatable {
    let users: [PlexHomeUser]

    private enum CodingKeys: String, CodingKey {
        case users
    }
}

nonisolated struct PlexHomeUser: Codable, Hashable, Identifiable {
    let id: Int?
    let uuid: String
    let title: String?
    let username: String?
    let email: String?
    let friendlyName: String?
    let thumb: URL?
    let protected: Bool?
    let pin: String?
    var admin: Bool? = nil
    var guest: Bool? = nil
    var restricted: Bool? = nil

    var displayName: String {
        [friendlyName, title, username].compactMap { $0?.isEmpty == false ? $0 : nil }.first ?? uuid
    }
}
