import Foundation
@testable import Strimr
import Testing

struct ExternalPlayerTemplateTests {
    private let streamURL =
        URL(string: "https://plex.example.com:32400/library/parts/1/file.mkv?X-Plex-Token=secret+token")!

    private func target(
        url: URL,
        title: String = "",
        startPosition: TimeInterval = 0,
        subtitles: [URL] = [],
    ) -> ExternalPlaybackTarget {
        ExternalPlaybackTarget(
            url: url,
            title: title,
            item: MediaIdentity(server: ServerIdentity(provider: .plex, id: "server-1"), itemID: "item-1"),
            duration: 3600,
            startPosition: startPosition,
            subtitles: subtitles,
        )
    }

    @Test func `substitutes every variable`() throws {
        let url = try ExternalPlayerTemplate.render(
            "myplayer://play?url={url}&name={title}&at={position}&back={callback}",
            target: target(url: #require(URL(string: "http://host/a")), title: "Movie", startPosition: 90.6),
        )

        #expect(url
            .absoluteString ==
            "myplayer://play?url=http%3A%2F%2Fhost%2Fa&name=Movie&at=90&back=strimr%3A%2F%2Fx-callback-url%2FplaybackDidFinish%3Fserver%3Dplex%3Aserver-1%26item%3Ditem-1%26duration%3D3600")
    }

    @Test func `fully encodes a stream URL that already has a query`() throws {
        let url = try ExternalPlayerTemplate.render("myplayer://play?url={url}", target: target(url: streamURL))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url
            .absoluteString ==
            "myplayer://play?url=https%3A%2F%2Fplex.example.com%3A32400%2Flibrary%2Fparts%2F1%2Ffile.mkv%3FX-Plex-Token%3Dsecret%2Btoken")
        #expect(components.queryItems?.count == 1)
        #expect(components.queryItems?.first?.value == streamURL.absoluteString)
    }

    @Test func `encodes special characters in the title`() throws {
        let url = try ExternalPlayerTemplate.render(
            "myplayer://play?url={url}&name={title}",
            target: target(url: #require(URL(string: "http://host/a")), title: "Tom & Jerry — S01E02 — 100% Café?"),
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.queryItems?.first(where: { $0.name == "name" })?
            .value == "Tom & Jerry — S01E02 — 100% Café?")
        #expect(components.queryItems?.count == 2)
    }

    @Test func `keeps the rest of the template untouched`() throws {
        let url = try ExternalPlayerTemplate.render(
            "my-player+x://open/now?mode=a%20b&u={url}",
            target: target(url: #require(URL(string: "http://h/v"))),
        )

        #expect(url.absoluteString == "my-player+x://open/now?mode=a%20b&u=http%3A%2F%2Fh%2Fv")
    }

    @Test func `repeats a list parameter for each subtitle`() throws {
        let url = try ExternalPlayerTemplate.render(
            "myplayer://play?url={url}&sub={subtitles}&name={title}",
            target: target(
                url: #require(URL(string: "http://h/v")),
                title: "T",
                subtitles: [
                    #require(URL(string: "http://h/s/1.srt?token=a&b")),
                    #require(URL(string: "http://h/s/2.srt")),
                ],
            ),
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.absoluteString ==
            "myplayer://play?url=http%3A%2F%2Fh%2Fv&sub=http%3A%2F%2Fh%2Fs%2F1.srt%3Ftoken%3Da%26b&sub=http%3A%2F%2Fh%2Fs%2F2.srt&name=T")
        #expect(components.queryItems?.filter { $0.name == "sub" }.map(\.value) == [
            "http://h/s/1.srt?token=a&b",
            "http://h/s/2.srt",
        ])
    }

    @Test func `drops a list parameter without subtitles`() throws {
        let withOthers = try ExternalPlayerTemplate.render(
            "myplayer://play?url={url}&sub={subtitles}&name={title}",
            target: target(url: #require(URL(string: "http://h/v")), title: "T"),
        )
        let alone = try ExternalPlayerTemplate.render(
            "myplayer://play/{url}?sub={subtitles}",
            target: target(url: #require(URL(string: "http://h/v"))),
        )

        #expect(withOthers.absoluteString == "myplayer://play?url=http%3A%2F%2Fh%2Fv&name=T")
        #expect(alone.absoluteString == "myplayer://play/http%3A%2F%2Fh%2Fv")
    }

    @Test func `rejects a list variable that is not a whole parameter value`() {
        #expect(throws: ExternalPlayerTemplateError.misplacedListVariable("subtitles")) {
            try ExternalPlayerTemplate.validate("myplayer://play?url={url}&sub=x{subtitles}")
        }
        #expect(throws: ExternalPlayerTemplateError.misplacedListVariable("subtitles")) {
            try ExternalPlayerTemplate.validate("myplayer://{subtitles}?url={url}")
        }
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
