import Foundation

/// What the user authenticates: a plex.tv account (several servers and Home users) or one Jellyfin user on one server.
enum MediaAccount: Codable, Hashable, Sendable, Identifiable {
    case plex(PlexAccount)
    case jellyfin(JellyfinAccount)

    var id: String {
        switch self {
        case let .plex(account):
            Self.plexID(account.id)
        case let .jellyfin(account):
            Self.jellyfinID(serverID: account.connection.serverID, userID: account.connection.userID)
        }
    }

    var provider: MediaProvider {
        switch self {
        case .plex:
            .plex
        case .jellyfin:
            .jellyfin
        }
    }

    var displayName: String {
        switch self {
        case let .plex(account):
            account.displayName
        case let .jellyfin(account):
            account.connection.username
        }
    }

    var plexAccount: PlexAccount? {
        guard case let .plex(account) = self else { return nil }
        return account
    }

    var jellyfinAccount: JellyfinAccount? {
        guard case let .jellyfin(account) = self else { return nil }
        return account
    }

    static func plexID(_ uuid: String) -> String {
        "plex:\(uuid)"
    }

    static func jellyfinID(serverID: String, userID: String) -> String {
        "jellyfin:\(serverID).\(userID)"
    }
}

struct PlexAccount: Codable, Hashable, Sendable {
    /// uuid of the plex.tv account. Its token lives in the Keychain under `strimr.plex.account.<id>`.
    let id: String
    let displayName: String
}

struct JellyfinAccount: Codable, Hashable, Sendable {
    /// The token keeps the pre-multi-server Keychain key, `strimr.jellyfin.token.<serverID>.<userID>`.
    let connection: JellyfinConnection

    var server: ServerIdentity {
        connection.serverIdentity
    }
}
