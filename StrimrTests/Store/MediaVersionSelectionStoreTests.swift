import Foundation
@testable import Strimr
import Testing

@MainActor
struct MediaVersionSelectionStoreTests {
    private let account = TrackSelectionAccount(
        server: ServerIdentity(provider: .plex, id: "server"),
        accountID: "account",
    )

    @Test func `saved preference survives a reload`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let scope = TrackSelectionScope.media(identity("movie"))

        MediaVersionSelectionStore(userDefaults: defaults).save(preference(at: 1), for: scope, account: account)
        let reloaded = MediaVersionSelectionStore(userDefaults: defaults)

        #expect(reloaded.preference(for: scope, account: account) == preference(at: 1))
    }

    @Test func `preferences are scoped by account`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = MediaVersionSelectionStore(userDefaults: defaults)
        let scope = TrackSelectionScope.series(identity("series"))
        let otherAccount = TrackSelectionAccount(server: account.server, accountID: "other")

        store.save(preference(at: 1), for: scope, account: account)

        #expect(store.preference(for: scope, account: otherAccount) == nil)
    }

    @Test func `oldest preferences are dropped beyond the cap`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = MediaVersionSelectionStore(userDefaults: defaults)
        let count = MediaVersionSelectionStore.maximumRecordCount + 1

        for index in 0 ..< count {
            store.save(preference(at: TimeInterval(index)), for: .media(identity("\(index)")), account: account)
        }

        #expect(store.records.count == MediaVersionSelectionStore.maximumRecordCount)
        #expect(store.preference(for: .media(identity("0")), account: account) == nil)
        #expect(store.preference(for: .media(identity("\(count - 1)")), account: account) != nil)
    }

    @Test func `removing a preference returns to automatic`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = MediaVersionSelectionStore(userDefaults: defaults)
        let scope = TrackSelectionScope.media(identity("movie"))

        store.save(preference(at: 1), for: scope, account: account)
        store.remove(for: scope, account: account)

        #expect(store.preference(for: scope, account: account) == nil)
    }

    private func identity(_ itemID: String) -> MediaIdentity {
        MediaIdentity(server: account.server, itemID: itemID)
    }

    private func preference(at time: TimeInterval) -> MediaVersionPreference {
        MediaVersionPreference(
            versionID: "version",
            signature: "1080:h264:mkv:sdr",
            updatedAt: Date(timeIntervalSince1970: time),
        )
    }
}
