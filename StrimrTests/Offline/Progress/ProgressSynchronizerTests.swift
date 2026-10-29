import Foundation
@testable import Strimr
import Testing

@MainActor
struct ProgressSynchronizerTests {
    private final class PlaybackService: FakeMediaService {
        var serverState = ServerItemWatchState(viewOffset: nil, viewCount: 0, isPlayed: false, lastViewedAt: nil)
        var refreshedState: ServerItemWatchState?
        var pushError: Error?
        private(set) var watchedItems: [(itemID: String, date: Date)] = []
        private(set) var pushedPositions: [(itemID: String, position: TimeInterval, date: Date)] = []
        private var stateReads = 0

        override func serverWatchState(itemID _: String) async throws -> ServerItemWatchState {
            stateReads += 1
            return stateReads > 1 ? refreshedState ?? serverState : serverState
        }

        override func markItemWatched(itemID: String, at date: Date) async throws {
            if let pushError {
                throw pushError
            }
            watchedItems.append((itemID, date))
        }

        override func pushItemPosition(
            itemID: String,
            position: TimeInterval,
            duration _: TimeInterval?,
            at date: Date,
        ) async throws {
            if let pushError {
                throw pushError
            }
            pushedPositions.append((itemID, position, date))
        }
    }

    private let database: TestOfflineDatabase
    private let store: OfflineStore
    private let service = PlaybackService()
    private let services: MediaServices

    init() throws {
        database = try TestOfflineDatabase()
        store = database.makeStore()
        services = MediaServices.fake(service)
    }

    private var owner: MediaOwner {
        services.owner
    }

    @Test func `an offline watched event newer than the server is pushed`() async {
        service.serverState = serverState(viewedAt: 1000)
        append(.watched, position: 600, at: 2000)

        let synced = await synchronize()

        #expect(synced)
        #expect(service.watchedItems.map(\.date) == [date(2000)])
        #expect(service.pushedPositions.isEmpty)
        #expect(store.pendingJournalCount(owner: owner) == 0)
    }

    @Test func `an offline position is pushed to a server that never saw the item`() async {
        append(.progress, position: 120, at: 2000)

        await synchronize()

        #expect(service.pushedPositions.map(\.position) == [120])
        #expect(service.pushedPositions.map(\.date) == [date(2000)])
        #expect(service.watchedItems.isEmpty)
    }

    @Test func `the server wins when it saw more recent activity`() async {
        service.serverState = serverState(viewedAt: 5000)
        append(.progress, position: 120, at: 2000)
        append(.watched, position: 600, at: 3000)

        let synced = await synchronize()

        #expect(synced)
        #expect(service.watchedItems.isEmpty)
        #expect(service.pushedPositions.isEmpty)
        #expect(store.pendingJournalCount(owner: owner) == 0)
    }

    @Test func `a rewatch started after the watched event also pushes its position`() async {
        append(.watched, position: 600, at: 2000)
        append(.progress, position: 90, at: 3000)

        await synchronize()

        #expect(service.watchedItems.map(\.date) == [date(2000)])
        #expect(service.pushedPositions.map(\.position) == [90])
    }

    @Test func `a position recorded before the watched event is not pushed`() async {
        append(.progress, position: 90, at: 2000)
        append(.watched, position: 600, at: 3000)

        await synchronize()

        #expect(service.watchedItems.map(\.date) == [date(3000)])
        #expect(service.pushedPositions.isEmpty)
    }

    @Test func `a position at the very start is not pushed`() async {
        append(.start, position: 0, at: 2000)

        await synchronize()

        #expect(service.pushedPositions.isEmpty)
        #expect(store.pendingJournalCount(owner: owner) == 0)
    }

    @Test func `the local watch state takes the server state after a sync`() async {
        store.setWatchState(
            OfflineWatchState(viewOffset: 120, viewCount: 0, played: false, lastViewedAt: date(2000), source: .local),
            itemID: "movie-1",
            owner: owner,
        )
        append(.progress, position: 120, at: 2000)
        service.refreshedState = ServerItemWatchState(
            viewOffset: 120, viewCount: 0, isPlayed: false, lastViewedAt: date(2001),
        )

        await synchronize()

        let state = store.watchState(itemID: "movie-1", owner: owner)
        #expect(state?.source == .server)
        #expect(state?.lastViewedAt == date(2001))
    }

    @Test func `an item deleted on the server is dropped from the journal`() async {
        service.pushError = JellyfinAPIError.itemUnavailable
        append(.watched, position: 600, at: 2000)

        let synced = await synchronize()

        #expect(synced)
        #expect(store.pendingJournalCount(owner: owner) == 0)
    }

    @Test func `an unreachable server keeps the journal for the next attempt`() async throws {
        service.pushError = URLError(.notConnectedToInternet)
        append(.watched, position: 600, at: 2000)

        let synced = await synchronize()

        #expect(!synced)
        let entry = try #require(store.pendingJournal(owner: owner).first)
        #expect(entry.attempts == 1)
    }

    @Test func `each item is synchronized on its own`() async {
        append(.progress, itemID: "movie-1", position: 60, at: 2000)
        append(.progress, itemID: "movie-2", position: 90, at: 2000)

        await synchronize()

        #expect(Set(service.pushedPositions.map(\.itemID)) == ["movie-1", "movie-2"])
    }

    @Test func `another owner's journal is left alone`() async {
        let otherOwner = MediaOwner(server: owner.server, userID: "someone-else")
        _ = store.appendJournal(
            itemID: "movie-1", owner: otherOwner, position: 60, duration: 600,
            event: .progress, occurredAt: date(2000), syncedAt: nil,
        )

        let synced = await synchronize()

        #expect(synced)
        #expect(service.pushedPositions.isEmpty)
        #expect(store.pendingJournalCount(owner: otherOwner) == 1)
    }

    // MARK: - Helpers

    @discardableResult
    private func synchronize() async -> Bool {
        await ProgressSynchronizer(store: store).synchronize(owner: owner, services: services)
    }

    private func append(
        _ event: ProgressJournalEvent,
        itemID: String = "movie-1",
        position: TimeInterval,
        at seconds: TimeInterval,
    ) {
        _ = store.appendJournal(
            itemID: itemID, owner: owner, position: position, duration: 600,
            event: event, occurredAt: date(seconds), syncedAt: nil,
        )
    }

    private func serverState(viewedAt seconds: TimeInterval) -> ServerItemWatchState {
        ServerItemWatchState(viewOffset: 30, viewCount: 0, isPlayed: false, lastViewedAt: date(seconds))
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
