import Foundation
@testable import Strimr
import Testing

@MainActor
struct OfflineStoreTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")
    private let owner = MediaOwner(server: ServerIdentity(provider: .jellyfin, id: "server-1"), userID: "user-1")
    private let otherOwner = MediaOwner(server: ServerIdentity(provider: .jellyfin, id: "server-1"), userID: "user-2")
    private let database: TestOfflineDatabase
    private let store: OfflineStore

    init() throws {
        database = try TestOfflineDatabase()
        store = database.makeStore()
    }

    // MARK: - Progress journal

    @Test func `a new position replaces the pending one of the same item`() {
        append(.progress, itemID: "movie-1", position: 60, at: 1000)
        append(.pause, itemID: "movie-1", position: 120, at: 2000)

        #expect(store.pendingJournal(owner: owner).map(\.position) == [120])
    }

    @Test func `a watched event is kept next to the pending position`() {
        append(.progress, itemID: "movie-1", position: 60, at: 1000)
        append(.watched, itemID: "movie-1", position: 600, at: 2000)

        #expect(store.pendingJournal(owner: owner).map(\.event) == ["progress", "watched"])
    }

    @Test func `a synchronized position is not replaced by the next one`() {
        let synced = append(.progress, itemID: "movie-1", position: 60, at: 1000)
        store.markJournalSynced(ids: [synced].compactMap(\.self), at: Date(timeIntervalSince1970: 1500))
        append(.progress, itemID: "movie-1", position: 120, at: 2000)

        #expect(store.pendingJournal(owner: owner).map(\.position) == [120])
    }

    @Test func `the pending journal is ordered by event date`() {
        append(.watched, itemID: "movie-2", position: 600, at: 3000)
        append(.progress, itemID: "movie-1", position: 60, at: 1000)

        #expect(store.pendingJournal(owner: owner).map(\.itemID) == ["movie-1", "movie-2"])
    }

    @Test func `the journal of another owner stays apart`() {
        append(.progress, itemID: "movie-1", position: 60, at: 1000)
        _ = store.appendJournal(
            itemID: "movie-1", owner: otherOwner, position: 90, duration: 600,
            event: .progress, occurredAt: Date(timeIntervalSince1970: 1000), syncedAt: nil,
        )

        #expect(store.pendingJournal(owner: owner).map(\.position) == [60])
        #expect(store.pendingJournalCount(owner: otherOwner) == 1)
    }

    @Test func `a failed entry stays pending and counts its attempts`() throws {
        let id = try #require(append(.progress, itemID: "movie-1", position: 60, at: 1000))

        store.markJournalFailed(ids: [id], error: "URLError")
        store.markJournalFailed(ids: [id], error: "URLError")

        let entry = try #require(store.pendingJournal(owner: owner).first)
        #expect(entry.attempts == 2)
        #expect(entry.lastError == "URLError")
    }

    @Test func `synchronized entries leave the pending journal`() throws {
        let id = try #require(append(.progress, itemID: "movie-1", position: 60, at: 1000))

        store.markJournalSynced(ids: [id])

        #expect(store.pendingJournalCount(owner: owner) == 0)
    }

    // MARK: - Media

    @Test func `stored media is read back in the requested order`() {
        store.store(media: [movie("movie-1", title: "A"), movie("movie-2", title: "B")], owner: owner)

        let items = store.mediaItems(ids: ["movie-2", "unknown", "movie-1"], owner: owner)

        #expect(items.map(\.id) == ["movie-2", "movie-1"])
    }

    @Test func `media is kept per owner`() {
        store.store(media: [movie("movie-1")], owner: owner)

        #expect(store.media(id: "movie-1", owner: otherOwner) == nil)
    }

    @Test func `search ignores case and accents`() {
        store.store(media: [movie("movie-1", title: "Amélie"), movie("movie-2", title: "Brazil")], owner: owner)

        #expect(store.search(query: "AMELIE", owner: owner).map(\.id) == ["movie-1"])
    }

    @Test func `search finds an episode by its series title`() {
        let episode = MediaItem.make(
            id: "episode-1", server: server, title: "Pilot", type: .episode, seriesTitle: "Breaking Bad",
        )
        store.store(media: [episode], owner: owner)

        #expect(store.search(query: "breaking", owner: owner).map(\.id) == ["episode-1"])
    }

    @Test func `a blank search finds nothing`() {
        store.store(media: [movie("movie-1")], owner: owner)

        #expect(store.search(query: "  ", owner: owner).isEmpty)
    }

    @Test func `series episodes are sorted by season then episode`() {
        store.store(media: [
            episode("s2e1", season: 2, episode: 1),
            episode("s1e2", season: 1, episode: 2),
            episode("s1e1", season: 1, episode: 1),
        ], owner: owner)

        #expect(store.episodes(ofSeries: "series-1", owner: owner).map(\.id) == ["s1e1", "s1e2", "s2e1"])
    }

    @Test func `library items are top-level titles sorted by title`() {
        store.store(media: [
            movie("movie-1", title: "Zodiac", libraryID: "library-1"),
            movie("movie-2", title: "Alien", libraryID: "library-1"),
            movie("movie-3", title: "Brazil", libraryID: "library-2"),
            episode("s1e1", season: 1, episode: 1, libraryID: "library-1"),
        ], owner: owner)

        #expect(store.libraryItems(libraryID: "library-1", owner: owner).map(\.id) == ["movie-2", "movie-1"])
    }

    @Test func `a list snapshot keeps the order of its items`() {
        store.store(
            list: [movie("movie-2"), movie("movie-1")].map(MediaDisplayItem.playable),
            key: "home",
            owner: owner,
        )

        #expect(store.list(key: "home", owner: owner)?.items.map(\.id) == ["movie-2", "movie-1"])
        #expect(store.list(key: "home", owner: otherOwner) == nil)
    }

    // MARK: - Watch state

    @Test func `pending local progress wins over the state the server returns`() {
        store.setWatchState(
            OfflineWatchState(viewOffset: 300, viewCount: 0, played: false, lastViewedAt: nil, source: .local),
            itemID: "movie-1",
            owner: owner,
        )

        store.store(media: [movie("movie-1", viewOffset: 10)], owner: owner)

        #expect(store.media(id: "movie-1", owner: owner)?.viewOffset == 300)
    }

    @Test func `the server state is applied when nothing is pending locally`() {
        store.store(media: [movie("movie-1", viewOffset: 10)], owner: owner)
        store.store(media: [movie("movie-1", viewOffset: 42)], owner: owner)

        #expect(store.media(id: "movie-1", owner: owner)?.viewOffset == 42)
    }

    @Test func `locally in progress items are the unsynchronized unfinished ones, latest first`() {
        store.store(media: [movie("movie-1"), movie("movie-2"), movie("movie-3")], owner: owner)
        setLocalState(itemID: "movie-1", offset: 100, played: false, viewedAt: 1000)
        setLocalState(itemID: "movie-2", offset: 100, played: false, viewedAt: 2000)
        setLocalState(itemID: "movie-3", offset: 100, played: true, viewedAt: 3000)

        #expect(store.locallyInProgressItems(owner: owner).map(\.id) == ["movie-2", "movie-1"])
    }

    @Test func `a played state without position clears the resume point`() {
        let item = movie("movie-1", viewOffset: 120).applying(
            OfflineWatchState(viewOffset: 0, viewCount: 1, played: true, lastViewedAt: nil, source: .local),
        )

        #expect(item.viewOffset == nil)
        #expect(item.watchState.isPlayed)
    }

    @Test func `a watch state never applies to a series`() {
        let series = MediaItem.make(id: "series-1", server: server, type: .series)

        let applied = series.applying(
            OfflineWatchState(viewOffset: 50, viewCount: 3, played: true, lastViewedAt: nil, source: .local),
        )

        #expect(applied.viewCount == series.viewCount)
    }

    // MARK: - Pinning and cache

    @Test func `pinned media survives clearing the cache`() {
        store.store(media: [movie("movie-1"), movie("movie-2")], owner: owner)
        pin(["movie-1"], downloadID: "download-1")

        store.clearCache()

        #expect(store.mediaItems(ids: ["movie-1", "movie-2"], owner: owner).map(\.id) == ["movie-1"])
    }

    @Test func `pinned media survives cache eviction`() {
        store.store(media: [movie("movie-1"), movie("movie-2")], owner: owner)
        pin(["movie-1"], downloadID: "download-1")

        store.evictCache(toFit: 0)

        #expect(store.mediaItems(ids: ["movie-1", "movie-2"], owner: owner).map(\.id) == ["movie-1"])
    }

    @Test func `deleting the last download of a media returns it to the cache`() {
        store.store(media: [movie("movie-1")], owner: owner)
        pin(["movie-1"], downloadID: "download-1")

        store.deleteDownload(id: "download-1")

        #expect(store.media(id: "movie-1", owner: owner) != nil)
        #expect(store.storageSizes().pinnedBytes == 0)
        store.clearCache()
        #expect(store.media(id: "movie-1", owner: owner) == nil)
    }

    @Test func `a media shared by two downloads stays pinned until both are deleted`() {
        store.store(media: [episode("s1e1", season: 1, episode: 1), series()], owner: owner)
        pin(["series-1", "s1e1"], downloadID: "download-1")
        pin(["series-1"], downloadID: "download-2")

        store.deleteDownload(id: "download-1")
        store.clearCache()

        #expect(store.media(id: "series-1", owner: owner) != nil)
        #expect(store.media(id: "s1e1", owner: owner) == nil)
    }

    @Test func `pinned artwork moves with its download`() {
        store.storeArtwork(Data([1, 2, 3]), key: "poster", owner: owner, width: nil, height: nil, pinned: false)

        pin([], artworkKeys: ["poster"], downloadID: "download-1")

        #expect(store.isArtworkPinned(key: "poster", owner: owner))
        let url = store.artworkFileURL(key: "poster", owner: owner)
        #expect(url?.deletingLastPathComponent().standardizedFileURL
            == database.database.pinnedArtworkDirectory.standardizedFileURL)
    }

    @Test func `an artwork can be found by its path without a size`() {
        store.storeArtwork(
            Data([1]),
            key: "/items/1/poster?w=100",
            owner: owner,
            width: 100,
            height: nil,
            pinned: false,
        )
        store.storeArtwork(
            Data([1, 2, 3]), key: "/items/1/poster?w=300", owner: owner, width: 300, height: nil, pinned: false,
        )

        let url = store.artworkFileURL(pathPrefix: "/items/1/poster", owner: owner)

        #expect(url == store.artworkFileURL(key: "/items/1/poster?w=300", owner: owner))
    }

    @Test func `clearing one owner's cache keeps the others`() {
        store.store(media: [movie("movie-1")], owner: owner)
        store.store(media: [movie("movie-1")], owner: otherOwner)

        store.clearCache(owner: owner)

        #expect(store.media(id: "movie-1", owner: owner) == nil)
        #expect(store.media(id: "movie-1", owner: otherOwner) != nil)
    }

    @Test func `deleting an owner's pinned data removes its journal only`() {
        append(.progress, itemID: "movie-1", position: 60, at: 1000)
        _ = store.appendJournal(
            itemID: "movie-1", owner: otherOwner, position: 90, duration: 600,
            event: .progress, occurredAt: Date(timeIntervalSince1970: 1000), syncedAt: nil,
        )

        store.deletePinnedData(owner: owner)

        #expect(store.pendingJournalCount(owner: owner) == 0)
        #expect(store.pendingJournalCount(owner: otherOwner) == 1)
    }

    // MARK: - Libraries

    @Test func `a pinned library shows next to the cached ones without duplicates`() {
        store.store(libraries: [library("library-1"), library("library-2")], owner: owner)
        store.store(pinnedLibrary: library("library-2"), owner: owner)
        store.store(pinnedLibrary: library("library-3"), owner: owner)

        #expect(store.libraries(owner: owner).map(\.id) == ["library-1", "library-2", "library-3"])
    }

    // MARK: - Downloads

    @Test func `downloads are read back with their metadata`() throws {
        try store.save(downloads: [
            DownloadItem.make(id: "download-1", itemID: "movie-1", server: server, status: .downloading),
        ])

        let downloads = try store.allDownloads()

        #expect(downloads.map(\.id) == ["download-1"])
        #expect(downloads.first?.status == .downloading)
        #expect(downloads.first?.metadata.videoFileName == "download-1.mp4")
    }

    @Test func `downloaded items are the completed ones of the owner, newest first`() throws {
        try store.save(downloads: [
            download("download-1", itemID: "movie-1", createdAt: 1000),
            download("download-2", itemID: "movie-2", createdAt: 2000),
            download("download-3", itemID: "movie-3", status: .downloading, createdAt: 3000),
            DownloadItem.make(id: "download-4", itemID: "movie-4", server: server, ownerID: otherOwner.id),
        ])

        #expect(store.downloadedItemIDsByDate(owner: owner) == ["movie-2", "movie-1"])
    }

    @Test func `downloads made before profiles get the owner of their server`() throws {
        let otherServer = ServerIdentity(provider: .jellyfin, id: "server-2")
        try store.save(downloads: [
            DownloadItem.make(id: "download-1", itemID: "movie-1", server: server),
            DownloadItem.make(id: "download-2", itemID: "movie-2", server: otherServer),
            DownloadItem.make(id: "download-3", itemID: "movie-3", server: server, ownerID: otherOwner.id),
        ])

        let assigned = store.assignOwner(owner, toUnownedDownloadsOn: server)

        #expect(assigned == 1)
        let owners = try Dictionary(uniqueKeysWithValues: store.allDownloads().map { ($0.id, $0.ownerID) })
        #expect(owners == ["download-1": owner.id, "download-2": nil, "download-3": otherOwner.id])
    }

    // MARK: - Helpers

    /// Links need their download row first, as the download manager saves it before pinning.
    private func pin(_ itemIDs: [String], artworkKeys: [String] = [], downloadID: String) {
        store.save(download: download(downloadID, itemID: itemIDs.first ?? "movie-1"))
        store.pin(itemIDs: itemIDs, artworkKeys: artworkKeys, downloadID: downloadID, owner: owner)
    }

    private func download(
        _ id: String,
        itemID: String,
        status: DownloadStatus = .completed,
        createdAt seconds: TimeInterval = 0,
    ) -> DownloadItem {
        DownloadItem.make(
            id: id,
            itemID: itemID,
            server: server,
            status: status,
            ownerID: owner.id,
            createdAt: Date(timeIntervalSince1970: seconds),
        )
    }

    @discardableResult
    private func append(
        _ event: ProgressJournalEvent,
        itemID: String,
        position: TimeInterval,
        at seconds: TimeInterval,
    ) -> Int64? {
        store.appendJournal(
            itemID: itemID, owner: owner, position: position, duration: 600,
            event: event, occurredAt: Date(timeIntervalSince1970: seconds), syncedAt: nil,
        )
    }

    private func setLocalState(itemID: String, offset: TimeInterval, played: Bool, viewedAt seconds: TimeInterval) {
        store.setWatchState(
            OfflineWatchState(
                viewOffset: offset,
                viewCount: played ? 1 : 0,
                played: played,
                lastViewedAt: Date(timeIntervalSince1970: seconds),
                source: .local,
            ),
            itemID: itemID,
            owner: owner,
        )
    }

    private func movie(
        _ id: String,
        title: String = "Title",
        libraryID: String? = nil,
        viewOffset: TimeInterval? = nil,
    ) -> MediaItem {
        MediaItem.make(id: id, server: server, title: title, librarySectionID: libraryID, viewOffset: viewOffset)
    }

    private func series() -> MediaItem {
        MediaItem.make(id: "series-1", server: server, title: "Series", type: .series)
    }

    private func episode(_ id: String, season: Int, episode: Int, libraryID: String? = nil) -> MediaItem {
        MediaItem.make(
            id: id,
            server: server,
            title: id,
            type: .episode,
            seasonNumber: season,
            episodeNumber: episode,
            seriesTitle: "Series",
            parentID: "season-\(season)",
            seriesID: "series-1",
            librarySectionID: libraryID,
        )
    }

    private func library(_ id: String) -> Library {
        Library(id: id, title: id, type: .movie, sectionId: nil, server: server)
    }
}
