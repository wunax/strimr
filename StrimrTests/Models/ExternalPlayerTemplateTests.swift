import Foundation
@testable import Strimr
import Testing

struct ExternalPlayerTemplateTests {
    private let streamURL = URL(string: "https://plex.example.com:32400/library/parts/1/file.mkv?X-Plex-Token=secret+token")!

    @Test func `substitutes every variable`() throws {
        let url = try ExternalPlayerTemplate.render(
            "myplayer://play?url={url}&name={title}&back={callback}",
            url: URL(string: "http://host/a")!,
            title: "Movie",
        )

        #expect(url.absoluteString == "myplayer://play?url=http%3A%2F%2Fhost%2Fa&name=Movie&back=strimr%3A%2F%2Fx-callback-url%2FplaybackDidFinish")
    }

    @Test func `fully encodes a stream URL that already has a query`() throws {
        let url = try ExternalPlayerTemplate.render("myplayer://play?url={url}", url: streamURL, title: "")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.absoluteString == "myplayer://play?url=https%3A%2F%2Fplex.example.com%3A32400%2Flibrary%2Fparts%2F1%2Ffile.mkv%3FX-Plex-Token%3Dsecret%2Btoken")
        #expect(components.queryItems?.count == 1)
        #expect(components.queryItems?.first?.value == streamURL.absoluteString)
    }

    @Test func `encodes special characters in the title`() throws {
        let url = try ExternalPlayerTemplate.render(
            "myplayer://play?url={url}&name={title}",
            url: URL(string: "http://host/a")!,
            title: "Tom & Jerry — S01E02 — 100% Café?",
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.queryItems?.first(where: { $0.name == "name" })?.value == "Tom & Jerry — S01E02 — 100% Café?")
        #expect(components.queryItems?.count == 2)
    }

    @Test func `keeps the rest of the template untouched`() throws {
        let url = try ExternalPlayerTemplate.render("my-player+x://open/now?mode=a%20b&u={url}", url: URL(string: "http://h/v")!, title: "")

        #expect(url.absoluteString == "my-player+x://open/now?mode=a%20b&u=http%3A%2F%2Fh%2Fv")
    }

    @Test func `requires the url variable`() {
        #expect(throws: ExternalPlayerTemplateError.missingURL) {
            try ExternalPlayerTemplate.validate("myplayer://play?name={title}")
        }
    }

    @Test func `rejects an unknown variable`() {
        #expect(throws: ExternalPlayerTemplateError.unknownVariable("uri")) {
            try ExternalPlayerTemplate.validate("myplayer://play?url={url}&u={uri}")
        }
    }

    @Test func `rejects a result without a scheme`() {
        #expect(throws: ExternalPlayerTemplateError.invalidURL) {
            try ExternalPlayerTemplate.validate("play?url={url}")
        }
        #expect(throws: ExternalPlayerTemplateError.invalidURL) {
            try ExternalPlayerTemplate.validate("my player://play?url={url}")
        }
    }

    @Test func `accepts a valid template`() throws {
        try ExternalPlayerTemplate.validate("myplayer://play?url={url}&x-success={callback}")
    }
}
