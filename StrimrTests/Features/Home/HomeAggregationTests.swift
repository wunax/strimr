import Foundation
@testable import Strimr
import Testing

@MainActor
struct HomeAggregationTests {
    private let plex = ServerIdentity(provider: .plex, id: "plex-a")
    private let jellyfin = ServerIdentity(provider: .jellyfin, id: "jf-b")

    @Test func `a single server keeps its rows and order`() {
        let rows = [
            continueWatching(on: plex, items: [movie("1", on: plex, date: 10)]),
            recentlyAdded("movies", on: plex, library: "1"),
            recentlyAdded("shows", on: plex, library: "2"),
        ]

        let merged = HomeAggregation.merge(
            [HomeAggregation.ServerHome(server: plex, serverName: "Plex", rows: rows)],
            showsServerNames: false,
        )

        #expect(merged.map(\.id) == [HomeRow.continueWatchingID, rows[1].id, rows[2].id])
        #expect(merged.map(\.serverName) == [nil, nil, nil])
    }

    @Test func `continue watching is merged and sorted by last viewed date`() {
        let homes = [
            home(plex, rows: [continueWatching(on: plex, items: [
                movie("p1", on: plex, date: 30),
                movie("p2", on: plex, date: 10),
            ])]),
            home(jellyfin, rows: [continueWatching(on: jellyfin, items: [movie("j1", on: jellyfin, date: 20)])]),
        ]

        let row = HomeAggregation.merge(homes, showsServerNames: true).first

        #expect(row?.id == HomeRow.continueWatchingID)
        #expect(row?.items.map(\.id) == ["p1", "j1", "p2"])
        #expect(row?.serverName == nil)
    }

    @Test func `duplicates across servers keep the most recent copy`() {
        let ids = ExternalIDs(imdb: "tt1")
        let homes = [
            home(plex, rows: [continueWatching(on: plex, items: [movie("p", on: plex, date: 10, ids: ids)])]),
            home(
                jellyfin,
                rows: [continueWatching(on: jellyfin, items: [movie("j", on: jellyfin, date: 20, ids: ids)])],
            ),
        ]

        let row = HomeAggregation.merge(homes, showsServerNames: true).first

        #expect(row?.items.map(\.server) == [jellyfin])
    }

    @Test func `the copy last played on this device wins`() {
        let ids = ExternalIDs(tmdb: "5")
        let homes = [
            home(plex, rows: [continueWatching(on: plex, items: [movie("p", on: plex, date: 10, ids: ids)])]),
            home(
                jellyfin,
                rows: [continueWatching(on: jellyfin, items: [movie("j", on: jellyfin, date: 20, ids: ids)])],
            ),
        ]
        let localDates = [MediaIdentity(server: plex, itemID: "p"): Date(timeIntervalSince1970: 1)]

        let row = HomeAggregation.merge(homes, showsServerNames: true) { localDates[$0] }.first

        #expect(row?.items.map(\.server) == [plex])
    }

    @Test func `items without ids are never merged`() {
        let homes = [
            home(plex, rows: [continueWatching(on: plex, items: [movie("p", on: plex, date: 10)])]),
            home(jellyfin, rows: [continueWatching(on: jellyfin, items: [movie("j", on: jellyfin, date: 20)])]),
        ]

        let row = HomeAggregation.merge(homes, showsServerNames: true).first

        #expect(row?.items.count == 2)
    }

    @Test func `next up is merged and follows reprendre`() {
        let ids = ExternalIDs(tvdb: "9")
        let homes = [
            home(plex, rows: [recentlyAdded("movies", on: plex, library: "1")]),
            home(jellyfin, rows: [
                nextUp(on: jellyfin, items: [episode("j1", on: jellyfin, ids: ids)]),
                continueWatching(on: jellyfin, items: [movie("j2", on: jellyfin, date: 5)]),
            ]),
        ]

        let merged = HomeAggregation.merge(homes, showsServerNames: true)

        #expect(merged.map(\.id).prefix(2) == [HomeRow.continueWatchingID, HomeRow.nextUpID])
        #expect(merged.last?.serverName == "plex-a name")
    }

    @Test func `recently added rows are never merged even with the same title`() {
        let homes = [
            home(plex, rows: [recentlyAdded("movies", on: plex, library: "1", title: "Recently Added Movies")]),
            home(jellyfin, rows: [recentlyAdded("movies", on: jellyfin, library: "1", title: "Recently Added Movies")]),
        ]

        let merged = HomeAggregation.merge(homes, showsServerNames: true)

        #expect(merged.count == 2)
        #expect(merged.map(\.serverName) == ["plex-a name", "jf-b name"])
    }

    @Test func `library rows follow the profile's library order`() {
        let homes = [
            home(plex, rows: [
                recentlyAdded("a", on: plex, library: "1"),
                recentlyAdded("b", on: plex, library: "2"),
            ]),
            home(jellyfin, rows: [recentlyAdded("c", on: jellyfin, library: "lib")]),
        ]
        let order = [
            LibraryIdentity(server: jellyfin, libraryID: "lib"),
            LibraryIdentity(server: plex, libraryID: "2"),
        ]

        let merged = HomeAggregation.merge(homes, libraryOrder: order, showsServerNames: true)

        #expect(merged.map { HomeAggregation.libraryIdentity(of: $0) } == [
            LibraryIdentity(server: jellyfin, libraryID: "lib"),
            LibraryIdentity(server: plex, libraryID: "2"),
            LibraryIdentity(server: plex, libraryID: "1"),
        ])
    }

    // MARK: - Row preferences

    @Test func `rows of an unreachable server keep their ids and come back in place`() {
        var preferences = HomeRowPreferences()
        let plexRow = recentlyAdded("a", on: plex, library: "1")
        let jellyfinRow = recentlyAdded("b", on: jellyfin, library: "1")
        let cw = continueWatching(on: plex, items: [movie("1", on: plex, date: 1)])
        preferences.setOrder([jellyfinRow.id, HomeRow.continueWatchingID, plexRow.id])
        preferences.setRow(plexRow.id, visible: false)

        // The Plex server is unreachable: its row is missing and the editor reorders what is left.
        preferences.setOrder([HomeRow.continueWatchingID, jellyfinRow.id])

        #expect(preferences.orderedRowIDs.contains(plexRow.id))
        #expect(preferences.hiddenRowIDs == [plexRow.id])

        let merged = HomeAggregation.merge(
            [home(plex, rows: [cw, plexRow]), home(jellyfin, rows: [jellyfinRow])],
            showsServerNames: true,
        )
        #expect(preferences.orderedRows(from: merged).map(\.id) == [
            HomeRow.continueWatchingID, jellyfinRow.id, plexRow.id,
        ])
        #expect(preferences.visibleRows(from: merged).map(\.id) == [HomeRow.continueWatchingID, jellyfinRow.id])
    }

    @Test func `rows of a new server go after the known ones`() {
        var preferences = HomeRowPreferences()
        let known = recentlyAdded("a", on: plex, library: "1")
        let new = recentlyAdded("b", on: jellyfin, library: "1")
        preferences.setOrder([known.id])

        let rows = HomeAggregation.merge(
            [home(jellyfin, rows: [new]), home(plex, rows: [known])],
            showsServerNames: true,
        )

        #expect(preferences.visibleRows(from: rows).map(\.id) == [known.id, new.id])
    }

    @Test func `a disabled server keeps its ids`() {
        let settings = SettingsManager(userDefaults: TestDefaults.make())
        let plexRow = recentlyAdded("a", on: plex, library: "1")
        settings.setHomeRowOrder([plexRow.id, HomeRow.continueWatchingID], profileID: "p")
        settings.setHomeRowVisibility(plexRow.id, visible: false, profileID: "p")

        // The home of a profile with the Plex server disabled only has the Jellyfin rows.
        settings.setHomeRowOrder([HomeRow.continueWatchingID], profileID: "p")

        #expect(settings.homeRowPreferences(profileID: "p").orderedRowIDs == [plexRow.id, HomeRow.continueWatchingID])
        #expect(settings.homeRowPreferences(profileID: "p").hiddenRowIDs == [plexRow.id])
    }

    @Test func `merged row ids carry no server`() {
        #expect(HomeRow.server(fromRowID: HomeRow.continueWatchingID) == nil)
        #expect(HomeRow.server(fromRowID: "home:jellyfin:jf-b:hub:x::/y") == jellyfin)
        #expect(HomeRow.migratedRowID("home:plex:plex-a:continueWatching") == HomeRow.continueWatchingID)
        #expect(HomeRow.migratedRowID("home:jellyfin:jf-b:nextUp") == HomeRow.nextUpID)
        #expect(HomeRow.migratedRowID("home:plex:plex-a:hub:a::/b") == "home:plex:plex-a:hub:a::/b")
    }

    // MARK: - Helpers

    private func home(_ server: ServerIdentity, rows: [HomeRow]) -> HomeAggregation.ServerHome {
        HomeAggregation.ServerHome(server: server, serverName: "\(server.id) name", rows: rows)
    }

    private func movie(_ id: String, on server: ServerIdentity, date: TimeInterval, ids: ExternalIDs = ExternalIDs())
        -> MediaItem
    {
        MediaItem.make(id: id, server: server, externalIDs: ids, lastViewedAt: Date(timeIntervalSince1970: date))
    }

    private func episode(_ id: String, on server: ServerIdentity, ids: ExternalIDs) -> MediaItem {
        MediaItem.make(id: id, server: server, type: .episode, externalIDs: ids, seasonNumber: 1, episodeNumber: 2)
    }

    private func continueWatching(on server: ServerIdentity, items: [MediaItem]) -> HomeRow {
        .continueWatching(
            server: server,
            hub: .make(id: "cw", title: "Continue Watching", items: items, server: server),
        )
    }

    private func nextUp(on server: ServerIdentity, items: [MediaItem]) -> HomeRow {
        .nextUp(server: server, hub: .make(id: "nextUp", title: "Next Up", items: items, server: server))
    }

    private func recentlyAdded(
        _ id: String,
        on server: ServerIdentity,
        library: String,
        title: String = "Recently Added",
    ) -> HomeRow {
        let items = [MediaItem.make(id: "\(id)-1", server: server, librarySectionID: library)]
        let hub = server.provider == .jellyfin
            ? Hub.make(id: "jellyfin.latest.\(library)", key: "", title: title, items: items, server: server)
            : Hub.make(
                id: id,
                key: "/hubs/home/recentlyAdded?type=1&sectionID=\(library)",
                title: title,
                items: items,
                server: server,
            )
        return .providerHub(server: server, hub: Hub(
            id: server.provider == .jellyfin ? hub.id : id,
            key: hub.key,
            hubKey: nil,
            title: title,
            size: hub.size,
            more: false,
            items: hub.items,
            server: server,
        ))
    }
}
