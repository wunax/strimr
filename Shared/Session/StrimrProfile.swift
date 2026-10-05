import CryptoKit
import Foundation

/// A Strimr profile: local (persisted by Strimr) or Plex Home (virtual, read live from plex.tv).
enum StrimrProfile: Identifiable, Hashable, Sendable {
    case local(LocalProfile)
    case plexHome(PlexHomeProfile)

    var id: String {
        switch self {
        case let .local(profile):
            profile.id
        case let .plexHome(profile):
            profile.id
        }
    }

    var name: String {
        switch self {
        case let .local(profile):
            profile.name
        case let .plexHome(profile):
            profile.user.displayName
        }
    }

    var isLocal: Bool {
        if case .local = self {
            return true
        }
        return false
    }

    /// While active, a managed Plex user cannot manage accounts, profiles or their connections.
    var isRestricted: Bool {
        guard case let .plexHome(profile) = self else { return false }
        return profile.user.restricted ?? false
    }

    var localProfile: LocalProfile? {
        guard case let .local(profile) = self else { return nil }
        return profile
    }

    var plexHomeProfile: PlexHomeProfile? {
        guard case let .plexHome(profile) = self else { return nil }
        return profile
    }
}

struct LocalProfile: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var name: String
    var pin: LocalProfilePIN?

    init(id: String = LocalProfile.makeID(), name: String, pin: LocalProfilePIN? = nil) {
        self.id = id
        self.name = name
        self.pin = pin
    }

    static func makeID() -> String {
        "local.\(UUID().uuidString.lowercased())"
    }
}

/// Salted SHA-256 of a local profile PIN; the PIN itself is never stored.
struct LocalProfilePIN: Codable, Hashable, Sendable {
    let salt: String
    let hash: String

    init(pin: String, salt: String = UUID().uuidString) {
        self.salt = salt
        hash = Self.digest(pin: pin, salt: salt)
    }

    func verify(_ pin: String) -> Bool {
        Self.digest(pin: pin, salt: salt) == hash
    }

    private static func digest(pin: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + pin).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct PlexHomeProfile: Hashable, Sendable, Identifiable {
    let accountID: String
    let user: PlexHomeUser

    var id: String {
        Self.id(userUUID: user.uuid)
    }

    static func id(userUUID: String) -> String {
        "plex.\(userUUID)"
    }

    /// The link to the parent account, implicit and never removable.
    var implicitLink: ProfileLink {
        ProfileLink(profileID: id, accountID: accountID, user: .plexHome(uuid: user.uuid))
    }
}

struct ProfileLink: Codable, Hashable, Sendable {
    let profileID: String
    let accountID: String
    let user: LinkedUser
}

enum LinkedUser: Codable, Hashable, Sendable {
    /// The Home token comes from `/home/users/{uuid}/switch` and is cached in the Keychain.
    case plexHome(uuid: String)
    /// Uses the token of the Jellyfin account.
    case jellyfin(userID: String)

    var userID: String {
        switch self {
        case let .plexHome(uuid):
            uuid
        case let .jellyfin(userID):
            userID
        }
    }
}

/// Servers of one account that a profile uses. Servers added later to the account follow the same rule.
enum ServerSelection: Codable, Hashable, Sendable {
    case allExcept(Set<String>)
    case only(Set<String>)

    static let all = ServerSelection.allExcept([])

    func isEnabled(_ serverID: String) -> Bool {
        switch self {
        case let .allExcept(disabled):
            !disabled.contains(serverID)
        case let .only(enabled):
            enabled.contains(serverID)
        }
    }

    func setting(_ serverID: String, enabled: Bool) -> ServerSelection {
        switch self {
        case var .allExcept(disabled):
            if enabled {
                disabled.remove(serverID)
            } else {
                disabled.insert(serverID)
            }
            return .allExcept(disabled)
        case var .only(allowed):
            if enabled {
                allowed.insert(serverID)
            } else {
                allowed.remove(serverID)
            }
            return .only(allowed)
        }
    }
}
