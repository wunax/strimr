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
    let accessToken: String
    let connections: [Connection]
}

struct PlexCloudUser: Codable, Equatable {
    let id: Int
    let uuid: String
    let username: String
    let title: String
    let email: String
    let friendlyName: String
    let locale: String?
    let confirmed: Bool
    let joinedAt: Int
    let authToken: String
}

struct PlexCloudPin: Codable, Equatable {
    let id: Int
    let code: String
    let product: String
    let trusted: Bool
    let clientIdentifier: String
    let expiresIn: Int
    let createdAt: String
    let expiresAt: String
    let authToken: String?
    let newRegistration: Bool?
}

struct PlexHome: Codable, Equatable {
    let id: Int
    let name: String
    let guestUserID: Int?
    let guestUserUUID: String?
    let guestEnabled: Bool
    let subscription: Bool?
    let users: [PlexHomeUser]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case guestUserID
        case guestUserUUID
        case guestEnabled
        case subscription
        case users
    }
}

struct PlexHomeUser: Codable, Equatable, Identifiable {
    struct Subscription: Codable, Equatable {
        let state: String?
        let type: String?
    }

    let id: Int
    let uuid: String
    let title: String
    let username: String?
    let email: String?
    let friendlyName: String?
    let thumb: URL?
    let hasPassword: Bool
    let restricted: Bool
    let updatedAt: Int?
    let restrictionProfile: String?
    let admin: Bool?
    let guest: Bool?
    let protected: Bool?
    let pin: String?
    let subscription: Subscription?
}
