import Foundation
@testable import Strimr
import Testing

struct TopShelfModelsTests {
    private struct Item: Equatable {
        let id: String
        let date: Date?
        let descriptor: MediaMatchDescriptor
    }

    @Test func `v2 sessions list every server`() throws {
        let sessions = try [
            TopShelfStoredSession(
                provider: "plex",
                serverURL: #require(URL(string: "https://plex.example.invalid")),
                serverID: "a",
                userID: nil,
            ),
            TopShelfStoredSession(
                provider: "jellyfin",
                serverURL: #require(URL(string: "https://jellyfin.example.invalid")),
                serverID: "b",
                userID: "user",
            ),
        ]

        let decoded = try TopShelfSessions.decode(v2: JSONEncoder().encode(sessions), v1: nil)

        #expect(decoded.sessions == sessions)
        #expect(decoded.legacyTokenKeys.isEmpty)
        #expect(sessions[1].tokenKey == "media.serverToken.jellyfin.b")
    }

    @Test func `the v1 session migrates with its unscoped token`() {
        let v1 = Data(#"{"provider":"plex","serverURL":"https://plex.example.invalid","serverID":"a"}"#.utf8)

        let decoded = TopShelfSessions.decode(v2: nil, v1: v1)

        #expect(decoded.sessions.map(\.serverID) == ["a"])
        #expect(decoded.legacyTokenKeys == ["media.serverToken.plex.a": "media.serverToken"])
    }

    @Test func `v2 wins over a leftover v1 session`() throws {
        let v2 = try JSONEncoder().encode([TopShelfStoredSession(
            provider: "jellyfin",
            serverURL: #require(URL(string: "https://jellyfin.example.invalid")),
            serverID: "b",
            userID: "user",
        )])
        let v1 = Data(#"{"provider":"plex","serverURL":"https://plex.example.invalid","serverID":"a"}"#.utf8)

        #expect(TopShelfSessions.decode(v2: v2, v1: v1).sessions.map(\.serverID) == ["b"])
    }

    @Test func `rows are merged by date and deduplicated`() {
        let shared = MediaMatchDescriptor(kind: .movie, guid: nil, externalIDs: ExternalIDs(imdb: "tt1"))
        let plexRow = [
            Item(id: "plex-old", date: Date(timeIntervalSince1970: 10), descriptor: shared),
            Item(id: "plex-new", date: Date(timeIntervalSince1970: 40), descriptor: none),
        ]
        let jellyfinRow = [Item(id: "jf", date: Date(timeIntervalSince1970: 30), descriptor: shared)]

        let merged = TopShelfSessions.merge([plexRow, jellyfinRow], date: \.date, descriptor: \.descriptor)

        #expect(merged.map(\.id) == ["plex-new", "jf"])
    }

    @Test func `a server that failed contributes nothing`() {
        let row = [Item(id: "a", date: nil, descriptor: none)]

        let merged = TopShelfSessions.merge([row, []], date: \.date, descriptor: \.descriptor)

        #expect(merged.map(\.id) == ["a"])
    }

    private var none: MediaMatchDescriptor {
        MediaMatchDescriptor(kind: .movie, guid: nil, externalIDs: ExternalIDs())
    }
}
