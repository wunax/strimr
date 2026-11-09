import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlexCloudNetworkClientTests {
    @Test func `requests carry the account token`() async throws {
        let stub = HTTPStub { _ in .status(204) }
        let client = PlexCloudNetworkClient(authToken: "token", clientIdentifier: "client", session: stub.session)

        try await client.send(path: "/user", method: "PUT", body: Data("{}".utf8))

        let request = try #require(stub.requests.first)
        #expect(request.url?.path == "/api/v2/user")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "token")
        #expect(request.httpBody == Data("{}".utf8))
    }
}
