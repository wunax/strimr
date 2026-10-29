import Foundation
@testable import Strimr
import Testing

@MainActor
struct ProgressSynchronizerTests {
    private final class PlaybackService: FakeMediaService {
        var serverState = ServerItemWatchState(viewOffset: nil, viewCount: 0, isPlayed: false, lastViewedAt: nil)
        private(set) var watchedItems: [(itemID: String, date: Date)] = []

        override func serverWatchState(itemID _: String) async throws -> ServerItemWatchState {
            serverState
        }

        override func markItemWatched(itemID: String, at date: Date) async throws {
            watchedItems.append((itemID, date))
        }
    }

    @Test func `an offline watched event newer than the server is pushed`() async throws {
        let database = try TestOfflineDatabase()
        let store = database.makeStore()
        let service = PlaybackService()
        service.serverState = ServerItemWatchState(
            viewOffset: 30, viewCount: 0, isPlayed: false, lastViewedAt: Date(timeIntervalSince1970: 1000),
        )
        let services = MediaServices.fake(service)
        let watchedAt = Date(timeIntervalSince1970: 2000)
        _ = store.appendJournal(
            itemID: "movie-1", owner: services.owner, position: 600, duration: 600,
            event: .watched, occurredAt: watchedAt, syncedAt: nil,
        )

        let synced = await ProgressSynchronizer(store: store).synchronize(owner: services.owner, services: services)

        #expect(synced)
        #expect(service.watchedItems.map(\.itemID) == ["movie-1"])
        #expect(service.watchedItems.map(\.date) == [watchedAt])
        #expect(store.pendingJournalCount(owner: services.owner) == 0)
    }
}
