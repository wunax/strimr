import Foundation
@testable import Strimr
import Testing

@MainActor
struct SeerrNetworkClientTests {
    @Test func `query values encode reserved characters`() async throws {
        let stub = HTTPStub { _ in .status(204) }
        let client = try SeerrNetworkClient(
            baseURL: #require(URL(string: "https://seerr.example.com")),
            session: stub.session,
        )

        try await client.send(
            path: "search",
            queryItems: [URLQueryItem(name: "query", value: "a;b: c+d&e=f's (g)")],
        )

        let request = try #require(stub.requests.first)
        #expect(request.url?.path == "/api/v1/search")
        #expect(request.url?.query == "query=a%3Bb%3A%20c%2Bd%26e%3Df%27s%20%28g%29")
    }
}
