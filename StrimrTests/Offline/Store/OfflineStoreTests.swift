import Foundation
@testable import Strimr
import Testing

@MainActor
struct OfflineStoreTests {
    private let owner = MediaOwner(server: ServerIdentity(provider: .jellyfin, id: "server-1"), userID: "user-1")
    private let database: TestOfflineDatabase
    private let store: OfflineStore

    init() throws {
        database = try TestOfflineDatabase()
        store = database.makeStore()
    }

    @Test func `a new position replaces the pending one of the same item`() {
        _ = store.appendJournal(
            itemID: "movie-1", owner: owner, position: 60, duration: 600,
            event: .progress, occurredAt: Date(timeIntervalSince1970: 1000), syncedAt: nil,
        )
        _ = store.appendJournal(
            itemID: "movie-1", owner: owner, position: 120, duration: 600,
            event: .pause, occurredAt: Date(timeIntervalSince1970: 2000), syncedAt: nil,
        )

        #expect(store.pendingJournal(owner: owner).map(\.position) == [120])
    }

    @Test func `a watched event is kept next to the pending position`() {
        _ = store.appendJournal(
            itemID: "movie-1", owner: owner, position: 60, duration: 600,
            event: .progress, occurredAt: Date(timeIntervalSince1970: 1000), syncedAt: nil,
        )
        _ = store.appendJournal(
            itemID: "movie-1", owner: owner, position: 600, duration: 600,
            event: .watched, occurredAt: Date(timeIntervalSince1970: 2000), syncedAt: nil,
        )

        #expect(store.pendingJournal(owner: owner).map(\.event) == ["progress", "watched"])
    }
}
