import Foundation
@testable import Strimr
import Testing

@MainActor
struct DeepLinkRouterTests {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 0)
    }

    @Test func `a newer link replaces the pending one`() {
        let router = DeepLinkRouter()
        router.receive(DeepLink(.tab(.home)))
        router.receive(DeepLink(.tab(.search)))
        #expect(router.pending == DeepLink(.tab(.search)))
    }

    @Test func `the same link twice in a row is handled once`() {
        let clock = Clock()
        let router = DeepLinkRouter(now: { clock.date })
        let link = DeepLink(.tab(.home))
        router.receive(link)
        router.clear(link)
        clock.date += 1
        router.receive(link)
        #expect(router.pending == nil)

        clock.date += DeepLinkRouter.duplicateWindow
        router.receive(link)
        #expect(router.pending == link)
    }

    @Test func `clearing ignores a link that was replaced`() {
        let router = DeepLinkRouter()
        let first = DeepLink(.tab(.home))
        let second = DeepLink(.tab(.search))
        router.receive(first)
        router.receive(second)
        router.clear(first)
        #expect(router.pending == second)
    }

    @Test func `urls that are not links are left to other handlers`() throws {
        let router = DeepLinkRouter()
        #expect(try !router.receive(#require(URL(string: "strimr://x-callback-url/playbackDidFinish"))))
        #expect(try router.receive(#require(URL(string: "strimr://open"))))
    }

    @Test func `a resolved profile leaves the link without one`() {
        let router = DeepLinkRouter()
        let link = DeepLink(.tab(.home), profile: "Anna")
        router.receive(link)
        router.awaitedProfileID = "local.anna"
        router.resolveProfile(of: link)
        #expect(router.pending == DeepLink(.tab(.home)))
        #expect(router.awaitedProfileID == nil)
    }
}
