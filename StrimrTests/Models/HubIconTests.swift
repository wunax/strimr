import Foundation
@testable import Strimr
import Testing

@MainActor
struct HubIconTests {
    private let plex = ServerIdentity(provider: .plex, id: "plex-a")
    private let jellyfin = ServerIdentity(provider: .jellyfin, id: "jf-b")

    @Test func `watching rows have their own icons`() {
        let movie = MediaItem.make(id: "1", server: plex)
        let continueRow = HomeRow.continueWatching(server: plex, hub: .make(
            id: "home.continue", title: "Continue Watching", items: [movie], server: plex,
        ))
        let nextUpRow = HomeRow.nextUp(server: jellyfin, hub: .make(
            id: "jellyfin.nextUp", title: "Next Up", items: [movie], server: jellyfin,
        ))

        #expect(HubIcon.systemImage(for: continueRow) == "play.circle")
        #expect(HubIcon.systemImage(for: nextUpRow) == "forward.end.circle")
    }

    @Test(arguments: [
        ("movie.recentlyadded.1", "clock"),
        ("home.movies.recent", "clock"),
        ("movie.recentlyreleased.1", "calendar"),
        ("tv.recentlyaired.2", "calendar"),
        ("movie.recentlyviewed.1", "eye"),
        ("home.movies.trending", "chart.line.uptrend.xyaxis"),
        ("tv.toprated.2", "star"),
        ("movie.topunwatched.1", "rosette"),
        ("movie.genre.1.2978", "theatermasks"),
        ("tv.moreingenre.2", "theatermasks"),
        ("movie.by.actor.or.director.1.12318", "person"),
        ("tv.startwatching.2", "play"),
        ("tv.rediscover.2", "arrow.counterclockwise"),
        ("home.ondeck", "forward.end.circle"),
        ("custom.collection.1.900", "square.stack"),
    ])
    func `plex hubs are matched on their identifier`(hubID: String, symbol: String) {
        let row = HomeRow.providerHub(server: plex, hub: .make(
            id: hubID, title: "Localized title", items: [.make(id: "1", server: plex)], server: plex,
        ))

        #expect(HubIcon.systemImage(for: row) == symbol)
    }

    @Test func `jellyfin latest rows share the recently added icon of plex`() {
        let row = HomeRow.providerHub(server: jellyfin, hub: .make(
            id: "jellyfin.latest.decade0", title: "Latest", items: [.make(id: "1", server: jellyfin)], server: jellyfin,
        ))

        #expect(HubIcon.systemImage(for: row) == "clock")
    }

    @Test(arguments: [
        ("jellyfin.library.inProgress.decade0", "play.circle"),
        ("jellyfin.library.nextUp.decade0", "forward.end.circle"),
        ("jellyfin.library.latestEpisodes.decade0", "clock"),
        ("jellyfin.library.latestMovies.decade0", "clock"),
        ("jellyfin.library.recommendation.3", "hand.thumbsup"),
    ])
    func `jellyfin library hubs are matched on their prefix`(hubID: String, symbol: String) {
        let hub = Hub.make(id: hubID, title: "Title", items: [.make(id: "1", server: jellyfin)], server: jellyfin)

        #expect(HubIcon.systemImage(for: hub) == symbol)
    }

    @Test func `plex library hubs get the icon of their home row`() {
        let hub = Hub.make(
            id: "movie.inprogress.1",
            title: "Continue",
            items: [.make(id: "1", server: plex)],
            server: plex,
        )

        #expect(HubIcon.systemImage(for: hub) == "play.circle")
    }

    @Test func `unknown hubs fall back to the kind of their items`() {
        let movies = HomeRow.providerHub(server: plex, hub: .make(
            id: "movie.curated.1.1", title: "Curated", items: [.make(id: "1", server: plex)], server: plex,
        ))
        let episodes = HomeRow.providerHub(server: jellyfin, hub: .make(
            id: "jellyfin.decade0",
            title: "Latest",
            items: [.make(id: "2", server: jellyfin, type: .episode), .make(id: "3", server: jellyfin, type: .series)],
            server: jellyfin,
        ))
        let mixed = HomeRow.providerHub(server: plex, hub: .make(
            id: "home.mixed",
            title: "Mixed",
            items: [.make(id: "4", server: plex), .make(id: "5", server: plex, type: .episode)],
            server: plex,
        ))

        #expect(HubIcon.systemImage(for: movies) == "film")
        #expect(HubIcon.systemImage(for: episodes) == "tv")
        #expect(HubIcon.systemImage(for: mixed) == nil)
    }
}
