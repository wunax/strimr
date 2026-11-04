import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlexAccountPreferencesServiceTests {
    @Test func `a change goes to the profile of the given user`() async throws {
        let stub = HTTPStub { request in
            request.httpMethod == "PUT" ? .status(204) : try .fixture("plex-account-profile")
        }
        let service = PlexAccountPreferencesService(token: { "home-user-token" }, session: stub.session)

        let updated = try await service.apply(.audioLanguage("fr"))

        let write = try #require(stub.requests.first)
        let url = try #require(write.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(write.httpMethod == "PUT")
        #expect(url.host() == "clients.plex.tv")
        #expect(url.path() == "/api/v2/user/profile")
        #expect(components.queryItems == [URLQueryItem(name: "defaultAudioLanguage", value: "fr")])
        #expect(write.value(forHTTPHeaderField: "X-Plex-Token") == "home-user-token")
        #expect(updated.subtitleMode == .always)
    }

    @Test func `no request is sent without the token of the user`() async {
        struct NoToken: Error {}
        let stub = HTTPStub()
        let service = PlexAccountPreferencesService(token: { throw NoToken() }, session: stub.session)

        await #expect(throws: NoToken.self) {
            try await service.load()
        }
        #expect(stub.requests.isEmpty)
    }
}
