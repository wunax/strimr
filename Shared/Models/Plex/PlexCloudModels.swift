import Foundation

struct PlexCloudResource: Codable, Equatable {
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

struct PlexCloudUser: Codable, Equatable {
    let id: Int?
    let uuid: String?
    let username: String?
    let title: String?
    let friendlyName: String?
    let authToken: String
    let thumb: String?
}

struct PlexCloudPin: Codable, Equatable {
    let id: Int
    let code: String
    let clientIdentifier: String
    let authToken: String?
}

struct PlexHome: Codable, Equatable {
    let users: [PlexHomeUser]

    private enum CodingKeys: String, CodingKey {
        case users
    }
}

struct PlexHomeUser: Codable, Hashable, Identifiable {
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
