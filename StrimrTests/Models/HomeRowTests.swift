import Foundation
@testable import Strimr
import Testing

@MainActor
struct HomeRowTests {
    private let plex = ServerIdentity(provider: .plex, id: "plex-a")
    private let jellyfin = ServerIdentity(provider: .jellyfin, id: "jf-b")

    @Test func `a plex hub row keeps its id when the hub's items change`() {
        let before = HomeRow.providerHub(
            server: plex,
            hub: hub("movie.recentlyadded.1", hubKey: "/library/metadata/1,2"),
        )
        let after = HomeRow.providerHub(
            server: plex,
            hub: hub("movie.recentlyadded.1", hubKey: "/library/metadata/3,1"),
        )

        #expect(before.id == after.id)
        #expect(before.id == "home:plex:plex-a:hub:movie.recentlyadded.1")
    }

    @Test func `a plex hub row keeps its id when the server picks another variant`() {
        let genre = HomeRow.providerHub(server: plex, hub: hub("movie.genre.1.7"))
        let otherGenre = HomeRow.providerHub(server: plex, hub: hub("movie.genre.1.12"))
        let actor = HomeRow.providerHub(server: plex, hub: hub("movie.by.actor.or.director.1.17457"))

        #expect(genre.id == otherGenre.id)
        #expect(genre.id == "home:plex:plex-a:hub:movie.genre.1")
        #expect(actor.id == "home:plex:plex-a:hub:movie.by.actor.or.director.1")
    }

    @Test func `plex hubs spanning libraries keep their identifier`() {
        #expect(HomeRow.stablePlexHubID("home.playlists") == "home.playlists")
        #expect(HomeRow.plexSectionID(fromHubID: "home.playlists") == nil)
        #expect(HomeRow.plexSectionID(fromHubID: "tv.recentlyadded.2") == "2")
    }

    @Test func `jellyfin hub row ids are unchanged`() {
        let row = HomeRow.providerHub(server: jellyfin, hub: hub("jellyfin.latest.lib", key: "/Users/u/Items/Latest"))

        #expect(row.id == "home:jellyfin:jf-b:hub:jellyfin.latest.lib::/Users/u/Items/Latest")
    }

    @Test func `plex rows without a section in their key find their library from the hub id`() {
        let row = HomeRow.providerHub(
            server: plex,
            hub: hub("movie.curated.3.1", key: "/hubs/items?identifier=movie.curated.3.1"),
        )

        #expect(HomeAggregation.libraryIdentity(of: row) == LibraryIdentity(server: plex, libraryID: "3"))
    }

    @Test func `rows off the server home are hidden until turned on`() {
        var preferences = HomeRowPreferences()

        #expect(preferences.isVisible("promoted", onServerHome: true))
        #expect(!preferences.isVisible("extra", onServerHome: false))

        preferences.setRow("extra", visible: true)
        preferences.setRow("promoted", visible: false)

        #expect(preferences.isVisible("extra", onServerHome: false))
        #expect(!preferences.isVisible("promoted", onServerHome: true))

        preferences.setRow("extra", visible: false)

        #expect(!preferences.isVisible("extra", onServerHome: false))
        #expect(preferences.shownRowIDs.isEmpty)
    }

    @Test func `removing a server forgets the rows turned on for it`() {
        var preferences = HomeRowPreferences()
        preferences.setRow("home:plex:plex-a:hub:movie.topunwatched.1", visible: true)
        preferences.setRow("home:jellyfin:jf-b:hub:x::/y", visible: true)

        preferences.removeRows(of: [plex])

        #expect(preferences.shownRowIDs == ["home:jellyfin:jf-b:hub:x::/y"])
    }

    @Test func `a row style is stored only while it differs from the default`() {
        var preferences = HomeRowPreferences()
        let row = HomeRow.providerHub(server: plex, hub: hub("movie.recentlyadded.1"))

        preferences.setStyle(.landscape, of: row)

        #expect(preferences.styled(row).style == .landscape)

        preferences.setStyle(.portrait, of: row)

        #expect(preferences.rowStyles.isEmpty)
        #expect(preferences.styled(row).style == .portrait)
    }

    @Test func `removing a server forgets its row styles`() {
        var preferences = HomeRowPreferences()
        preferences.setStyle(.landscape, of: HomeRow.providerHub(server: plex, hub: hub("movie.recentlyadded.1")))

        preferences.removeRows(of: [plex])

        #expect(preferences.isEmpty)
    }

    private func hub(_ id: String, key: String = "", hubKey: String? = nil) -> Hub {
        Hub(id: id, key: key, hubKey: hubKey, title: id, size: 1, more: false, items: [], server: nil)
    }
}
