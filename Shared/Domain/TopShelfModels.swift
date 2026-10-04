import Foundation

// Shared with the Top Shelf extension: keep this file free of app-only types.

/// A server of the active profile as the Top Shelf extension sees it. Its token lives in the shared Keychain under
/// `tokenKey`.
nonisolated struct TopShelfStoredSession: Codable, Hashable, Sendable {
    let provider: String
    let serverURL: URL
    let serverID: String
    let userID: String?

    var tokenKey: String {
        Self.tokenKey(provider: provider, serverID: serverID)
    }

    static func tokenKey(provider: String, serverID: String) -> String {
        "media.serverToken.\(provider).\(serverID)"
    }
}

nonisolated enum TopShelfSessions {
    static let appGroup = "group.com.github.wunax.strimr"
    static let keychainService = "com.github.wunax.strimr.top-shelf"
    static let sessionsKey = "media.session.v2"
    static let legacySessionKey = "media.session.v1"
    static let legacyTokenKey = "media.serverToken"
    // Plex-only format that predates v1.
    static let legacyPlexTokenKey = "plex.serverToken"
    static let legacyPlexURLKey = "plex.serverURL"

    /// Sessions stored by the app: the v2 list, or the single v1 session of the previous version whose token used the
    /// unscoped key.
    static func decode(v2: Data?, v1: Data?) -> (sessions: [TopShelfStoredSession], legacyTokenKeys: [String: String]) {
        if let v2, let sessions = try? JSONDecoder().decode([TopShelfStoredSession].self, from: v2) {
            return (sessions, [:])
        }
        guard let v1, let session = try? JSONDecoder().decode(TopShelfStoredSession.self, from: v1) else {
            return ([], [:])
        }
        return ([session], [session.tokenKey: legacyTokenKey])
    }

    /// Merges the rows of several servers: newest first, one entry per title. Servers that failed contribute nothing.
    static func merge<Item>(
        _ rows: [[Item]],
        date: (Item) -> Date?,
        descriptor: (Item) -> MediaMatchDescriptor,
    ) -> [Item] {
        let sorted = rows.flatMap(\.self).enumerated().sorted { lhs, rhs in
            switch (date(lhs.element), date(rhs.element)) {
            case let (left?, right?) where left != right:
                left > right
            case (_?, nil):
                true
            case (nil, _?):
                false
            default:
                lhs.offset < rhs.offset
            }
        }.map(\.element)
        return MediaMatching.group(sorted, descriptor: descriptor).compactMap(\.first)
    }
}
