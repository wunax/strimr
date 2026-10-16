import Foundation
@testable import Strimr
import Testing

struct ExternalPlayerTests {
    private let target = ExternalPlaybackTarget(
        url: URL(string: "http://server.example.com/Videos/item-1/stream.mkv?Static=true&api_key=token")!,
        title: "Show — S01E02 — Pilot",
        item: MediaIdentity(server: ServerIdentity(provider: .plex, id: "server-1"), itemID: "item-1"),
        duration: nil,
    )
    private let encodedURL = "http%3A%2F%2Fserver.example.com%2FVideos%2Fitem-1%2Fstream.mkv%3FStatic%3Dtrue%26api_key%3Dtoken"
    private let encodedCallback =
        "strimr%3A%2F%2Fx-callback-url%2FplaybackDidFinish%3Fserver%3Dplex%3Aserver-1%26item%3Ditem-1"

    @Test(arguments: [Platform.iOS, .macOS, .tvOS])
    func `infuse uses its x-callback URL everywhere`(platform: Platform) throws {
        let request = ExternalPlayer.known(.infuse).launchRequest(for: target, platform: platform)

        #expect(try request ==
            .url(
                #require(URL(
                    string: "infuse://x-callback-url/play?url=\(encodedURL)&x-success=\(encodedCallback)&x-error=\(encodedCallback)",
                )),
            ))
    }

    @Test(arguments: [Platform.iOS, .tvOS])
    func `vlc uses its x-callback URL on iOS and tvOS`(platform: Platform) throws {
        let request = ExternalPlayer.known(.vlc).launchRequest(for: target, platform: platform)

        #expect(try request ==
            .url(
                #require(URL(
                    string: "vlc-x-callback://x-callback-url/stream?url=\(encodedURL)&x-success=\(encodedCallback)",
                )),
            ))
    }

    @Test func `vlc opens the stream in the app on macOS`() {
        let request = ExternalPlayer.known(.vlc).launchRequest(for: target, platform: .macOS)

        #expect(request == .open(target.url, bundleID: "org.videolan.vlc"))
    }

    @Test func `iina uses its weblink URL on macOS`() throws {
        let request = ExternalPlayer.known(.iina).launchRequest(for: target, platform: .macOS)

        #expect(try request == .url(#require(URL(string: "iina://weblink?url=\(encodedURL)"))))
    }

    @Test func `native player passes the title and start position on tvOS`() throws {
        var target = target
        target.startPosition = 754.8
        let request = ExternalPlayer.known(.nativePlayer).launchRequest(for: target, platform: .tvOS)

        #expect(try request ==
            .url(
                #require(URL(
                    string: "nativeplayer://x-callback-url/play?url=\(encodedURL)&filename=Show%20%E2%80%94%20S01E02%20%E2%80%94%20Pilot&position=754&x-success=\(encodedCallback)&x-error=\(encodedCallback)",
                )),
            ))
    }

    @Test func `native player passes each subtitle on tvOS`() throws {
        var target = target
        target.subtitles = try [
            #require(URL(string: "http://server.example.com/s/1.srt")),
            #require(URL(string: "http://server.example.com/s/2.srt")),
        ]
        let request = ExternalPlayer.known(.nativePlayer).launchRequest(for: target, platform: .tvOS)

        #expect(try request ==
            .url(
                #require(URL(
                    string: "nativeplayer://x-callback-url/play?url=\(encodedURL)&filename=Show%20%E2%80%94%20S01E02%20%E2%80%94%20Pilot&position=0&sub=http%3A%2F%2Fserver.example.com%2Fs%2F1.srt&sub=http%3A%2F%2Fserver.example.com%2Fs%2F2.srt&x-success=\(encodedCallback)&x-error=\(encodedCallback)",
                )),
            ))
    }

    @Test func `unsupported players have no launch request`() {
        #expect(ExternalPlayer.known(.iina).launchRequest(for: target, platform: .iOS) == nil)
        #expect(ExternalPlayer.known(.iina).launchRequest(for: target, platform: .tvOS) == nil)
        #expect(ExternalPlayer.known(.nativePlayer).launchRequest(for: target, platform: .iOS) == nil)
        #expect(ExternalPlayer.known(.nativePlayer).launchRequest(for: target, platform: .macOS) == nil)
        #expect(!ExternalPlayerID.iina.isSupported(on: .iOS))
        #expect(ExternalPlayerID.nativePlayer.isSupported(on: .tvOS))
    }

    @Test func `detection schemes come from the templates`() {
        #expect(ExternalPlayerID.infuse.scheme(on: .iOS) == "infuse")
        #expect(ExternalPlayerID.vlc.scheme(on: .tvOS) == "vlc-x-callback")
        #expect(ExternalPlayerID.vlc.scheme(on: .macOS) == nil)
        #expect(ExternalPlayerID.iina.scheme(on: .macOS) == "iina")
        #expect(ExternalPlayerID.nativePlayer.scheme(on: .tvOS) == "nativeplayer")
    }

    @Test(arguments: [Platform.iOS, .macOS, .tvOS])
    func `custom player renders its template`(platform: Platform) throws {
        let player = ExternalPlayer.custom(CustomExternalPlayer(
            name: "Mine",
            template: "mine://play?u={url}&t={title}",
        ))

        #expect(try player
            .launchRequest(for: target, platform: platform) ==
            .url(
                #require(URL(string: "mine://play?u=\(encodedURL)&t=Show%20%E2%80%94%20S01E02%20%E2%80%94%20Pilot")),
            ))
    }

    @Test func `invalid custom player has no launch request`() {
        let player = ExternalPlayer.custom(CustomExternalPlayer(name: "Mine", template: "mine://play?u={uri}"))

        #expect(player.launchRequest(for: target, platform: .iOS) == nil)
    }

    @Test func `selection resolves to a player`() {
        let valid = CustomExternalPlayer(name: "Mine", template: "mine://play?u={url}")

        #expect(ExternalPlayer(selection: nil, custom: valid) == nil)
        #expect(ExternalPlayer(selection: .known(.vlc), custom: valid) == .known(.vlc))
        #expect(ExternalPlayer(selection: .custom, custom: valid) == .custom(valid))
        #expect(ExternalPlayer(selection: .custom, custom: nil) == nil)
        #expect(ExternalPlayer(selection: .custom, custom: CustomExternalPlayer(name: "Mine", template: "mine://")) ==
            nil)
        #expect(ExternalPlayer(selection: .custom, custom: CustomExternalPlayer(name: " ", template: valid.template)) ==
            nil)
    }

    @Test func `episode title includes the series and episode number`() {
        let server = ServerIdentity(provider: .plex, id: "server-1")
        let episode = MediaItem.make(
            id: "1",
            server: server,
            title: "Pilot",
            type: .episode,
            seasonNumber: 1,
            episodeNumber: 2,
            seriesTitle: "Show",
        )
        let movie = MediaItem.make(id: "2", server: server, title: "Movie")

        #expect(ExternalPlaybackTarget.title(for: episode) == "Show — S01E02 — Pilot")
        #expect(ExternalPlaybackTarget.title(for: movie) == "Movie")
    }
}
