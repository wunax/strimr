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
}
