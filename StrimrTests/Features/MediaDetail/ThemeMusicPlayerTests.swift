import Foundation
@testable import Strimr
import Testing

struct ThemeMusicPlayerTests {
    private let server = ServerIdentity(provider: .plex, id: "server-a")
    private let url = URL(string: "https://example.com/theme")!

    @Test func `a show and its episodes share the same theme`() {
        let show = ThemeMusic(path: "/library/metadata/100/theme/1700000000", url: url, server: server)
        let episode = ThemeMusic(path: "/library/metadata/100/theme/1600000000", url: url, server: server)

        #expect(show.key == episode.key)
    }

    @Test func `different shows or servers do not share a theme`() {
        let show = ThemeMusic(path: "/library/metadata/100/theme/1700000000", url: url, server: server)
        let otherShow = ThemeMusic(path: "/library/metadata/200/theme/1700000000", url: url, server: server)
        let otherServer = ThemeMusic(
            path: "/library/metadata/100/theme/1700000000",
            url: url,
            server: ServerIdentity(provider: .plex, id: "server-b"),
        )

        #expect(show.key != otherShow.key)
        #expect(show.key != otherServer.key)
    }

    @Test func `paths without a version suffix are kept as is`() {
        #expect(ThemeMusic.stablePath("/library/metadata/100/theme") == "/library/metadata/100/theme")
        #expect(ThemeMusic.stablePath("/library/metadata/100/theme/abc") == "/library/metadata/100/theme/abc")
    }
}
