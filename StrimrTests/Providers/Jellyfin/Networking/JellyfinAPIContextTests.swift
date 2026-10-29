import Foundation
@testable import Strimr
import Testing

@MainActor
struct JellyfinAPIContextTests {
    private let connection = JellyfinConnection(
        baseURL: URL(string: "https://jellyfin.example.test")!,
        serverID: "server-1",
        serverName: "Server",
        serverVersion: "10.10.0",
        userID: "user-1",
        username: "user",
    )

    @Test func `validating a server reads its public system info`() async throws {
        let stub = HTTPStub { _ in
            .json(#"{"Id": "server-1", "ServerName": "Server", "Version": "10.10.0"}"#)
        }
        let context = JellyfinAPIContext(session: stub.session)

        let (info, _) = try await context.validateServerURL("https://jellyfin.example.test")

        #expect(info.id == "server-1")
        #expect(stub.requests.map(\.url?.path) == ["/System/Info/Public"])
    }

    @Test func `an unauthorized response asks to sign in again`() async throws {
        let stub = HTTPStub { _ in .status(401) }
        let context = JellyfinAPIContext(session: stub.session)
        context.configure(connection: connection, token: "token")
        var authenticationRequired = false
        context.configureAuthenticationRequiredHandler { authenticationRequired = true }

        await #expect(throws: JellyfinAPIError.authenticationRequired) {
            try await context.refreshCurrentUser()
        }
        #expect(authenticationRequired)
        #expect(stub.requests.first?.value(forHTTPHeaderField: "X-Emby-Token") == "token")
    }

    @Test(arguments: [
        (403, JellyfinAPIError.permissionDenied),
        (404, JellyfinAPIError.itemUnavailable),
        (500, JellyfinAPIError.httpStatus(500)),
    ])
    func `an error status maps to its error`(statusCode: Int, expected: JellyfinAPIError) async {
        let stub = HTTPStub { _ in .status(statusCode) }
        let context = authenticatedContext(stub)

        await #expect(throws: expected) {
            try await context.refreshCurrentUser()
        }
    }

    @Test func `a network failure reports the server as unreachable`() async {
        let stub = HTTPStub { _ in throw URLError(.cannotConnectToHost) }
        let context = authenticatedContext(stub)

        await #expect(throws: JellyfinAPIError.serverUnreachable) {
            try await context.refreshCurrentUser()
        }
    }

    @Test func `an undecodable body is an invalid response`() async {
        let stub = HTTPStub { _ in .json("not json") }
        let context = authenticatedContext(stub)

        await #expect(throws: JellyfinAPIError.invalidResponse) {
            try await context.refreshCurrentUser()
        }
    }

    @Test func `calls without a session ask to sign in`() async {
        let stub = HTTPStub()
        let context = JellyfinAPIContext(session: stub.session)

        await #expect(throws: JellyfinAPIError.authenticationRequired) {
            try await context.refreshCurrentUser()
        }
        #expect(stub.requests.isEmpty)
    }

    @Test(arguments: [
        ("jellyfin.example.test", "http://jellyfin.example.test/System/Info/Public"),
        ("  HTTPS://jellyfin.example.test/jf//  ", "https://jellyfin.example.test/jf/System/Info/Public"),
        ("https://jellyfin.example.test:8920?x=1#top", "https://jellyfin.example.test:8920/System/Info/Public"),
    ])
    func `a typed server address is normalized`(address: String, expectedURL: String) async throws {
        let stub = HTTPStub { _ in .json(#"{"Id": "server-1", "ServerName": "Server", "Version": "10.10.0"}"#) }
        let context = JellyfinAPIContext(session: stub.session)

        _ = try await context.validateServerURL(address)

        #expect(stub.requests.first?.url?.absoluteString == expectedURL)
    }

    @Test(arguments: ["", "ftp://jellyfin.example.test", "https://user:pass@jellyfin.example.test"])
    func `an unusable server address is rejected without a request`(address: String) async {
        let stub = HTTPStub()
        let context = JellyfinAPIContext(session: stub.session)

        await #expect(throws: JellyfinAPIError.invalidServerURL) {
            try await context.validateServerURL(address)
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func `a server without an identifier is not supported`() async {
        let stub = HTTPStub { _ in .json(#"{"Id": "", "ServerName": "Server", "Version": "10.10.0"}"#) }
        let context = JellyfinAPIContext(session: stub.session)

        await #expect(throws: JellyfinAPIError.unsupportedServer) {
            try await context.validateServerURL("https://jellyfin.example.test")
        }
    }

    private func authenticatedContext(_ stub: HTTPStub) -> JellyfinAPIContext {
        let context = JellyfinAPIContext(session: stub.session)
        context.configure(connection: connection, token: "token")
        return context
    }
}
