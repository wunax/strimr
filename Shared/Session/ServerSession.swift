import Foundation

enum ServerSessionStatus: Equatable, Sendable {
    case connecting
    case ready
    case unreachable
    /// The token of this server was revoked; the other servers keep working.
    case needsReauthentication
}

/// One server of the active profile.
struct ServerSession: Identifiable {
    let identity: ServerIdentity
    let name: String
    let accountID: String
    /// Built once the server is enabled and connected.
    var services: MediaServices?
    var isEnabled: Bool
    var status: ServerSessionStatus

    var id: ServerIdentity {
        identity
    }

    /// Ready and enabled: the servers aggregated views query.
    var isActive: Bool {
        isEnabled && status == .ready && services != nil
    }
}
