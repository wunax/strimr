import Foundation
@testable import Strimr
import Testing

@MainActor
struct JellyfinAccountPreferencesServiceTests {
    private let connection = JellyfinConnection(
        baseURL: URL(string: "https://jellyfin.example.test")!,
        serverID: "server-1",
        serverName: "Server",
        serverVersion: "10.10.0",
        userID: "user-1",
        username: "user",
    )

    private nonisolated static func configuration(in request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func `a change keeps the fields the app does not know`() async throws {
        let stub = HTTPStub { request in
            request.httpMethod == "POST" ? .status(204) : try .fixture("jellyfin-user-preferences")
        }
        let context = JellyfinAPIContext(session: stub.session)
        context.configure(connection: connection, token: "token")
        let service = JellyfinAccountPreferencesService(context: { context })

        _ = try await service.apply(.subtitleMode(.always))

        let write = try #require(stub.requests.first { $0.httpMethod == "POST" })
        let written = try Self.configuration(in: write)
        #expect(written["SubtitleMode"] as? String == "Always")
        #expect(written["OrderedViews"] as? [String] == ["view-1", "view-2"])
        #expect(written["EnableNextEpisodeAutoPlay"] as? Bool == true)
    }

    @Test func `simultaneous writes do not overwrite each other`() async throws {
        let lock = NSLock()
        nonisolated(unsafe) var stored: [String: Any] = ["SubtitleMode": "Default"]
        let stub = HTTPStub { request in
            try lock.withLock {
                if request.httpMethod == "POST" {
                    stored = try Self.configuration(in: request)
                    return .status(204)
                }
                let user: [String: Any] = ["Id": "user-1", "Name": "user", "Configuration": stored]
                return try .json(JSONSerialization.data(withJSONObject: user))
            }
        }
        let context = JellyfinAPIContext(session: stub.session)
        context.configure(connection: connection, token: "token")

        async let first: Void = context.updateUserConfiguration { configuration in
            AccountPreferenceChange.subtitleMode(.always).apply(toJellyfinConfiguration: &configuration)
            return true
        }
        async let second: Void = context.enableTrackSelectionMemory(for: .audio)
        _ = try await (first, second)

        lock.withLock {
            #expect(stored["SubtitleMode"] as? String == "Always")
            #expect(stored["RememberAudioSelections"] as? Bool == true)
        }
    }

    @Test func `no write is sent when nothing changes`() async throws {
        let stub = HTTPStub { _ in
            .json(#"{"Id": "user-1", "Name": "user", "Configuration": {"RememberAudioSelections": true}}"#)
        }
        let context = JellyfinAPIContext(session: stub.session)
        context.configure(connection: connection, token: "token")

        try await context.enableTrackSelectionMemory(for: .audio)

        #expect(stub.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func `a server decision of no subtitles beats the default flag of the file`() throws {
        let source = try Fixtures.decode(JellyfinMediaSource.self, from: "jellyfin-media-source-subtitles-off")

        #expect(source.serverSubtitleIndex(validIndices: [2, 3]) == nil)
    }

    @Test func `the subtitle chosen by the server is used`() throws {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-movie-versions")
        let source = try #require(item.mediaSources?.first { $0.defaultSubtitleStreamIndex != nil })
        let index = try #require(source.defaultSubtitleStreamIndex)

        #expect(source.serverSubtitleIndex(validIndices: [index]) == index)
        #expect(source.serverSubtitleIndex(validIndices: []) == nil)
    }
}
