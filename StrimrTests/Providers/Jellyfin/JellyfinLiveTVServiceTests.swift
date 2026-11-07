import Foundation
@testable import Strimr
import Testing

@MainActor
struct JellyfinLiveTVServiceTests {
    @Test func `a channel without a number falls back to its channel number`() async throws {
        let stub = HTTPStub { _ in
            .json(#"""
            {"Items": [
                {"Id": "a", "Name": "Alpha", "Number": "4", "ChannelNumber": "9"},
                {"Id": "b", "Name": "Beta", "ChannelNumber": "7"},
                {"Id": "c", "Name": "Gamma", "Number": ""}
            ], "TotalRecordCount": 3}
            """#)
        }
        let context = JellyfinAPIContext(session: stub.session)
        try context.configure(
            connection: JellyfinConnection(
                baseURL: #require(URL(string: "https://jellyfin.example.test")),
                serverID: "server-1",
                serverName: "Server",
                serverVersion: "10.10.0",
                userID: "user-1",
                username: "user",
            ),
            token: "token",
        )
        let service = JellyfinLiveTVService(
            context: context,
            server: ServerIdentity(provider: .jellyfin, id: "live-tv-number-test"),
        )

        let numbers = try await service.channels().map { "\($0.providerID)=\($0.number ?? "none")" }

        #expect(numbers == ["a=4", "b=7", "c=none"])
    }
}
