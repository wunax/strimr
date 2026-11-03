import Foundation
@testable import Strimr
import Testing

@MainActor
struct HomeHeroSlidesTests {
    private let plex = ServerIdentity(provider: .plex, id: "plex-a")

    @Test func `resume slides follow the continue watching row up to ten items`() {
        let items = (1 ... 12).map { MediaItem.make(id: "m\($0)", server: plex, viewOffset: 60) }
        let rows = [continueWatching(items)]

        let slides = HomeHeroSlides.resume(from: rows)

        #expect(slides.map(\.media.id) == items.prefix(10).map(\.id))
        #expect(slides.allSatisfy(\.isResume))
    }

    @Test func `a single item to resume is enough`() {
        let slides = HomeHeroSlides.resume(from: [continueWatching([MediaItem.make(id: "only", server: plex)])])

        #expect(slides.map(\.media.id) == ["only"])
    }

    @Test func `no continue watching row means no hero`() {
        #expect(HomeHeroSlides.resume(from: []).isEmpty)
    }

    @Test func `an episode to resume is labelled with its season and episode`() {
        let episode = MediaItem.make(
            id: "ep",
            server: plex,
            type: .episode,
            seasonNumber: 2,
            episodeNumber: 5,
            seriesTitle: "Show",
        )

        let slide = HomeHeroSlides.resume(from: [continueWatching([episode])]).first

        #expect(slide?.eyebrow == episode.tertiaryLabel)
        #expect(slide?.media.primaryLabel == "Show")
    }

    @Test func `the watching items gather continue watching and next up`() {
        let resume = MediaItem.make(id: "r", server: plex)
        let next = MediaItem.make(id: "n", server: plex, type: .episode)
        let rows: [HomeRow] = [
            continueWatching([resume]),
            .nextUp(server: plex, hub: .make(id: "nextUp", title: "Next Up", items: [next], server: plex)),
            .providerHub(
                server: plex,
                hub: .make(
                    id: "hub",
                    title: "Hub",
                    items: [MediaItem.make(id: "h", server: plex)],
                    server: plex,
                ),
            ),
        ]

        #expect(HomeHeroSlides.watchingItems(in: rows).map(\.id) == ["r", "n"])
    }

    @Test func `featured slides keep the reason of their candidate`() {
        let candidate = FeaturedCandidate(
            item: MediaItem.make(id: "s", server: plex, type: .series),
            reason: .newSeason,
            newSeasonNumber: 3,
        )

        let slide = HomeHeroSlides.featured([candidate]).first

        #expect(slide?.badge == .featured(.newSeason, newSeasonNumber: 3, collectionTitle: nil))
        #expect(slide?.isResume == false)
    }

    private func continueWatching(_ items: [MediaItem]) -> HomeRow {
        .continueWatching(server: plex, hub: .make(id: "cw", title: "Continue Watching", items: items, server: plex))
    }
}
