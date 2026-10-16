import Foundation
@testable import Strimr
import Testing

struct ExternalPlaybackCallbackTests {
    private let item = MediaIdentity(server: ServerIdentity(provider: .jellyfin, id: "server-1"), itemID: "item-1")

    private func callbackURL(duration: TimeInterval? = 3600) -> URL {
        ExternalPlaybackCallback.url(for: ExternalPlaybackTarget(
            url: URL(string: "http://host/video")!,
            title: "",
            item: item,
            duration: duration,
        ))
    }

    private func appending(_ query: String, to url: URL) throws -> URL {
        try #require(URL(string: "\(url.absoluteString)&\(query)"))
    }

    @Test func `callback URL carries the item and duration`() {
        #expect(callbackURL().absoluteString ==
            "strimr://x-callback-url/playbackDidFinish?server=jellyfin:server-1&item=item-1&duration=3600")
        #expect(callbackURL(duration: nil).absoluteString ==
            "strimr://x-callback-url/playbackDidFinish?server=jellyfin:server-1&item=item-1")
    }

    @Test func `reads the position and progress appended on success`() throws {
        let url = try appending(
            "lastPlayedUrl=http%3A%2F%2Fhost%2Fvideo&position=1200&progress=0.3333",
            to: callbackURL(),
        )

        #expect(ExternalPlaybackCallback(url: url) == ExternalPlaybackCallback(
            item: item,
            duration: 3600,
            outcome: .finished(position: 1200, progress: 0.3333),
        ))
    }

    @Test func `a callback without parameters is a finish without progress`() {
        #expect(ExternalPlaybackCallback(url: callbackURL())?.outcome == .finished(position: nil, progress: nil))
    }

    @Test func `reads the error appended on failure`() throws {
        let url = try appending("errorCode=100&errorMessage=Unsupported%20content", to: callbackURL())

        #expect(ExternalPlaybackCallback(url: url)?.outcome == .failed(message: "Unsupported content"))
    }

    @Test func `an error code alone is a failure without message`() throws {
        let url = try appending("errorCode=400", to: callbackURL())

        #expect(ExternalPlaybackCallback(url: url)?.outcome == .failed(message: nil))
    }

    @Test func `a callback without the item still parses`() throws {
        let callback = try ExternalPlaybackCallback(url: #require(URL(
            string: "strimr://x-callback-url/playbackDidFinish?position=10",
        )))

        #expect(callback?.item == nil)
        #expect(callback?.outcome == .finished(position: 10, progress: nil))
    }

    @Test func `other Strimr links are not callbacks`() throws {
        #expect(try ExternalPlaybackCallback(url: #require(URL(string: "strimr://play/123?type=movie"))) == nil)
        #expect(try ExternalPlaybackCallback(url: #require(URL(string: "other://x-callback-url/playbackDidFinish"))) ==
            nil)
    }
}
