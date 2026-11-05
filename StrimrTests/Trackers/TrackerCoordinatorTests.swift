import Foundation
@testable import Strimr
import Testing

@MainActor
struct TrackerCoordinatorTests {
    private let defaults = TestDefaults.make()
    private let secureStore = InMemorySecureStore()
    private let detail = FakeTrackerDetailService()

    private final class Clients {
        var byService: [TrackerService: FakeTrackerClient] = [:]
        var invalidate: [TrackerService: () -> Void] = [:]
        var update: [TrackerService: (TrackerSession) -> Void] = [:]
    }

    private let clients = Clients()
    private final class TestNow {
        var date = Date(timeIntervalSince1970: 1000)
    }

    private let clock = TestNow()

    private var store: TrackerAccountStore {
        TrackerAccountStore(userDefaults: defaults, secureStore: secureStore)
    }

    private var queue: TrackerWriteQueue {
        TrackerWriteQueue(userDefaults: defaults)
    }

    private func coordinator(isDisabled: Bool = false) -> TrackerCoordinator {
        let clients = clients
        let clock = clock
        return TrackerCoordinator(
            isDisabled: isDisabled,
            store: store,
            queue: queue,
            now: { clock.date },
        ) { service, _, onUpdated, onInvalidated in
            let client = FakeTrackerClient(service: service, resendThrottle: 0)
            clients.byService[service] = client
            clients.update[service] = onUpdated
            clients.invalidate[service] = onInvalidated
            return client
        }
    }

    private func connected(_ services: [TrackerService] = [.trakt]) async -> TrackerCoordinator {
        let coordinator = coordinator()
        coordinator.activate(profileID: "p1")
        for service in services {
            await coordinator.connect(service, session: TrackerFixtures.session)
        }
        return coordinator
    }

    private func settle(_ coordinator: TrackerCoordinator) async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        await coordinator.waitForFlush()
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }

    // MARK: - Accounts

    @Test func `connecting saves the tokens and the account name`() async {
        let coordinator = await connected()

        #expect(store.session(.trakt, profileID: "p1") == TrackerFixtures.session)
        #expect(coordinator.state(for: .trakt).isConnected)
        #expect(coordinator.state(for: .trakt).settings.username == "alice")
    }

    @Test func `a renewed session replaces the saved one`() async throws {
        let coordinator = await connected()
        let renewed = TrackerSession(accessToken: "a2", refreshToken: "r2", expiresAt: .distantFuture)

        let update = try #require(clients.update[.trakt])
        update(renewed)

        withExtendedLifetime(coordinator) {
            #expect(store.session(.trakt, profileID: "p1") == renewed)
        }
    }

    @Test func `an expired session asks to reconnect and removes the tokens`() async throws {
        let coordinator = await connected()

        let invalidate = try #require(clients.invalidate[.trakt])
        invalidate()

        #expect(store.session(.trakt, profileID: "p1") == nil)
        #expect(!coordinator.state(for: .trakt).isConnected)
        #expect(coordinator.state(for: .trakt).settings.needsReconnect)
    }

    @Test func `disconnecting revokes and forgets the account and its writes`() async throws {
        let coordinator = await connected()
        let client = try #require(clients.byService[.trakt])

        await coordinator.disconnect(.trakt)

        #expect(client.revokeCount == 1)
        #expect(store.session(.trakt, profileID: "p1") == nil)
        #expect(!coordinator.state(for: .trakt).isConnected)
    }

    @Test func `each profile has its own account`() async {
        let coordinator = await connected()

        coordinator.activate(profileID: "p2")
        #expect(!coordinator.state(for: .trakt).isConnected)

        coordinator.activate(profileID: "p1")
        #expect(coordinator.state(for: .trakt).isConnected)
    }

    @Test func `removing a profile removes its account`() async {
        let coordinator = await connected()

        coordinator.removeProfile("p1")

        #expect(store.session(.trakt, profileID: "p1") == nil)
        #expect(coordinator.activeProfileID == nil)
    }

    // MARK: - Watched marks

    @Test func `a watched movie reaches every connected service`() async {
        let coordinator = await connected([.trakt, .simkl])

        coordinator.setPlayed(true, item: TrackerFixtures.movieItem(), detail: detail)
        await settle(coordinator)

        #expect(clients.byService[.trakt]?.added.first?.first?.item == TrackerFixtures.movie)
        #expect(clients.byService[.simkl]?.added.first?.first?.item == TrackerFixtures.movie)
    }

    @Test func `an unwatched mark removes from the history`() async {
        let coordinator = await connected()

        coordinator.setPlayed(false, item: TrackerFixtures.movieItem(), detail: detail)
        await settle(coordinator)

        #expect(clients.byService[.trakt]?.removed.first == [TrackerFixtures.movie])
    }

    @Test func `a watched season goes out as its episodes`() async {
        let coordinator = await connected()
        detail.items["series"] = TrackerFixtures.seriesItem()
        let season = MediaItem.make(id: "s1", server: TrackerFixtures.server, type: .season, parentID: "series")
        detail.episodesByID["s1"] = [
            TrackerFixtures.episodeItem(id: "e1", number: 1),
            TrackerFixtures.episodeItem(id: "e2", number: 2),
        ]

        coordinator.setPlayed(true, item: season, detail: detail)
        await settle(coordinator)

        #expect(clients.byService[.trakt]?.added.first?.map(\.item) == [
            TrackerFixtures.episode(1),
            TrackerFixtures.episode(2),
        ])
    }

    @Test func `a long list goes out in batches`() async {
        let coordinator = await connected()
        detail.items["series"] = TrackerFixtures.seriesItem()
        let season = MediaItem.make(id: "s1", server: TrackerFixtures.server, type: .season, parentID: "series")
        detail.episodesByID["s1"] = (1 ... 120).map { TrackerFixtures.episodeItem(id: "e\($0)", number: $0) }

        coordinator.setPlayed(true, item: season, detail: detail)
        await settle(coordinator)

        #expect(clients.byService[.trakt]?.added.map(\.count) == [50, 50, 20])
    }

    @Test func `a later watch keeps the date it happened`() async {
        let coordinator = await connected()
        detail.items["movie"] = TrackerFixtures.movieItem()
        let date = Date(timeIntervalSince1970: 500)

        coordinator.noteWatched(itemID: "movie", at: date, detail: detail)
        await settle(coordinator)

        #expect(clients.byService[.trakt]?.added.first?.first?.watchedAt == date)
    }

    @Test func `an excluded library sends nothing`() async {
        let coordinator = await connected()
        detail.library = "lib"
        let key = TrackerCoordinator.libraryKey(server: TrackerFixtures.server, libraryID: "lib")
        coordinator.setLibrary(key, isExcluded: true, for: .trakt)

        coordinator.setPlayed(true, item: TrackerFixtures.movieItem(), detail: detail)
        await settle(coordinator)

        #expect(clients.byService[.trakt]?.added.isEmpty == true)
    }

    @Test func `an unknown library sends nothing once a filter exists`() async {
        let coordinator = await connected()
        detail.library = nil
        coordinator.setLibrary("other", isExcluded: true, for: .trakt)

        coordinator.setPlayed(true, item: TrackerFixtures.movieItem(), detail: detail)
        await settle(coordinator)

        #expect(clients.byService[.trakt]?.added.isEmpty == true)
    }

    @Test func `a disabled service sends nothing`() async {
        let coordinator = await connected()
        coordinator.setEnabled(false, for: .trakt)

        coordinator.setPlayed(true, item: TrackerFixtures.movieItem(), detail: detail)
        await settle(coordinator)

        #expect(clients.byService[.trakt]?.added.isEmpty == true)
    }

    @Test func `demo mode never touches a tracker`() {
        let coordinator = coordinator(isDisabled: true)
        store.saveSession(TrackerFixtures.session, service: .trakt, profileID: "p1")

        coordinator.activate(profileID: "p1")

        #expect(clients.byService.isEmpty)
        #expect(coordinator.beginPlayback(
            of: TrackerFixtures.movieItem(),
            detail: detail,
            resumeOffset: nil,
        ) == nil)
    }

    // MARK: - Queue

    private func failingOnce(with error: Error) async -> (TrackerCoordinator, FakeTrackerClient) {
        let coordinator = await connected()
        let client = clients.byService[.trakt]!
        client.historyFailures = [error]
        coordinator.setPlayed(true, item: TrackerFixtures.movieItem(), detail: detail)
        await settle(coordinator)
        return (coordinator, client)
    }

    /// The coordinator owns its own queue instance, so what it kept is read back from a flush.
    @Test func `a network failure keeps the write for the next flush`() async {
        let (coordinator, client) = await failingOnce(with: URLError(.notConnectedToInternet))
        #expect(client.added.isEmpty)

        coordinator.flushQueue()
        await settle(coordinator)

        #expect(client.added.count == 1)
    }

    @Test func `an unknown title leaves the queue`() async {
        let (coordinator, client) = await failingOnce(with: TrackerAPIError.notFound)

        coordinator.flushQueue()
        await settle(coordinator)

        #expect(client.added.isEmpty)
    }

    @Test func `a rate limit holds the service until the delay passes`() async {
        let (coordinator, client) = await failingOnce(with: TrackerAPIError.rateLimited(retryAfter: 100))

        coordinator.flushQueue()
        await settle(coordinator)
        #expect(client.added.isEmpty)

        clock.date.addTimeInterval(101)
        coordinator.flushQueue()
        await settle(coordinator)
        #expect(client.added.count == 1)
    }

    @Test func `an account limit is shown and holds the service`() async {
        let (coordinator, client) = await failingOnce(with: TrackerAPIError.accountLimit)

        #expect(coordinator.state(for: .trakt).issue == .accountLimit)

        clock.date.addTimeInterval(100_000)
        coordinator.flushQueue()
        await settle(coordinator)
        #expect(client.added.isEmpty)
    }

    @Test func `a repeated server failure eventually drops the write`() async {
        let (coordinator, client) = await failingOnce(with: TrackerAPIError.server(status: 503))

        for _ in 1 ..< TrackerWriteQueue.maxAttempts {
            client.historyFailures = [TrackerAPIError.server(status: 503)]
            coordinator.flushQueue()
            await settle(coordinator)
        }
        coordinator.flushQueue()
        await settle(coordinator)

        #expect(client.added.isEmpty)
    }

    @Test func `writes waiting on a former account never reach a new one`() async throws {
        let coordinator = await connected()
        let first = try #require(clients.byService[.trakt])
        first.historyFailures = [URLError(.notConnectedToInternet)]
        coordinator.setPlayed(true, item: TrackerFixtures.movieItem(), detail: detail)
        await settle(coordinator)

        store.saveSettings(
            TrackerAccountSettings(username: "former"),
            service: .trakt,
            profileID: "p1",
        )
        await coordinator.connect(.trakt, session: TrackerFixtures.session)
        await settle(coordinator)

        #expect(clients.byService[.trakt]?.added.isEmpty == true)
    }

    // MARK: - Playback

    private func playback(
        _ coordinator: TrackerCoordinator,
    ) async throws -> TrackerPlaybackSession {
        let session = try #require(coordinator.beginPlayback(
            of: TrackerFixtures.movieItem(),
            detail: detail,
            resumeOffset: nil,
        ))
        await settle(coordinator)
        return session
    }

    @Test func `a playback reports to the connected service`() async throws {
        let coordinator = await connected()
        let session = try await playback(coordinator)

        session.playing(position: 100, duration: 1000)
        await settle(coordinator)

        #expect(clients.byService[.trakt]?.reports.first?.event == .start)
    }

    @Test func `nothing starts without a connected service`() {
        let coordinator = coordinator()
        coordinator.activate(profileID: "p1")

        #expect(coordinator.beginPlayback(
            of: TrackerFixtures.movieItem(),
            detail: detail,
            resumeOffset: nil,
        ) == nil)
    }

    @Test func `a clip is not reported`() async {
        let coordinator = await connected()
        let clip = MediaItem.make(id: "clip", server: TrackerFixtures.server, type: .clip)

        #expect(coordinator.beginPlayback(of: clip, detail: detail, resumeOffset: nil) == nil)
    }

    @Test func `a failed stop past the threshold is kept as a watch`() async throws {
        let coordinator = await connected()
        let client = try #require(clients.byService[.trakt])
        let session = try await playback(coordinator)
        session.playing(position: 100, duration: 1000)
        await settle(coordinator)

        client.reportFailures = [URLError(.networkConnectionLost)]
        session.stopped(position: 850, duration: 1000)
        await settle(coordinator)
        #expect(client.added.isEmpty)

        coordinator.flushQueue()
        await settle(coordinator)

        #expect(client.added.first?.first?.item == TrackerFixtures.movie)
        #expect(client.added.first?.first?.watchedAt == clock.date)
    }

    @Test func `a failed stop below the threshold is forgotten`() async throws {
        let coordinator = await connected()
        let client = try #require(clients.byService[.trakt])
        let session = try await playback(coordinator)
        session.playing(position: 100, duration: 1000)
        await settle(coordinator)

        client.reportFailures = [URLError(.networkConnectionLost)]
        session.stopped(position: 500, duration: 1000)
        await settle(coordinator)
        coordinator.flushQueue()
        await settle(coordinator)

        #expect(client.added.isEmpty)
    }

    @Test func `a playback keeps its account after a profile switch`() async throws {
        let coordinator = await connected()
        let client = try #require(clients.byService[.trakt])
        let session = try await playback(coordinator)

        coordinator.activate(profileID: "p2")
        session.playing(position: 100, duration: 1000)
        await settle(coordinator)

        #expect(client.reports.count == 1)
    }

    @Test func `a playback stops reporting once its account is disconnected`() async throws {
        let coordinator = await connected()
        let client = try #require(clients.byService[.trakt])
        let session = try await playback(coordinator)

        await coordinator.disconnect(.trakt)
        session.playing(position: 100, duration: 1000)
        await settle(coordinator)

        #expect(client.reports.isEmpty)
    }
}
