import Foundation
@testable import Strimr
import Testing

@MainActor
struct ExploreWatchlistTests {
    private final class Recorder {
        var items: [ExploreItem] = []
        var mutations: [(Bool, ExploreWatchlistTarget)] = []
        var fetchCount = 0
        var failure: Error?
        var pendingMutation: CheckedContinuation<Void, Never>?
    }

    private func watchlist(_ recorder: Recorder, holdsMutations: Bool = false) -> ExploreWatchlist {
        ExploreWatchlist(
            reloadDelay: .seconds(3600),
            fetch: {
                recorder.fetchCount += 1
                return recorder.items
            },
            mutate: { add, target in
                if holdsMutations {
                    await withCheckedContinuation { recorder.pendingMutation = $0 }
                }
                if let failure = recorder.failure {
                    throw failure
                }
                recorder.mutations.append((add, target))
            },
        )
    }

    @Test func `membership is unknown until the watchlist has loaded`() async throws {
        let recorder = Recorder()
        recorder.items = [.make(externalIDs: ExternalIDs(imdb: "tt1"))]
        let watchlist = watchlist(recorder)
        let target = ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs(imdb: "tt1"))

        #expect(watchlist.contains(target) == nil)
        try await watchlist.load()
        #expect(watchlist.contains(target) == true)
    }

    @Test func `a server item matches on any shared id of the same kind`() async throws {
        let recorder = Recorder()
        recorder.items = [.make(kind: .movie, externalIDs: ExternalIDs(imdb: "tt1", tmdb: "10"))]
        let watchlist = watchlist(recorder)
        try await watchlist.load()

        #expect(watchlist.contains(ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs(tmdb: "10"))) == true)
        #expect(watchlist.contains(ExploreWatchlistTarget(kind: .show, externalIDs: ExternalIDs(tmdb: "10"))) == false)
        #expect(watchlist.contains(ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs(tmdb: "11"))) == false)
    }

    @Test func `the watchlist loads once until forced`() async throws {
        let recorder = Recorder()
        let watchlist = watchlist(recorder)

        try await watchlist.load()
        try await watchlist.load()
        #expect(recorder.fetchCount == 1)

        try await watchlist.load(force: true)
        #expect(recorder.fetchCount == 2)
    }

    @Test func `a change shows before the source is read again`() async throws {
        let recorder = Recorder()
        let watchlist = watchlist(recorder)
        try await watchlist.load()
        let target = ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs(tmdb: "10"))

        try await watchlist.set(true, target: target)

        #expect(watchlist.contains(target) == true)
        #expect(recorder.mutations.count == 1)
        #expect(recorder.mutations.first?.0 == true)
    }

    @Test func `a failed change is rolled back`() async throws {
        let recorder = Recorder()
        recorder.failure = ExploreTestError()
        let watchlist = watchlist(recorder)
        try await watchlist.load()
        let target = ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs(tmdb: "10"))

        await #expect(throws: ExploreTestError.self) {
            try await watchlist.set(true, target: target)
        }
        #expect(watchlist.contains(target) == false)
        #expect(!watchlist.isUpdating(target))
    }

    @Test func `the same change is not sent twice while it runs`() async throws {
        let recorder = Recorder()
        let watchlist = watchlist(recorder, holdsMutations: true)
        try await watchlist.load()
        let target = ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs(tmdb: "10"))

        let first = Task { try await watchlist.set(true, target: target) }
        while recorder.pendingMutation == nil {
            await Task.yield()
        }
        #expect(watchlist.isUpdating(target))
        let second = try await watchlist.set(true, target: target)
        recorder.pendingMutation?.resume()

        #expect(second == false)
        #expect(try await first.value == true)
        #expect(recorder.mutations.count == 1)
    }

    @Test func `a reload replaces the pending changes with the source's state`() async throws {
        let recorder = Recorder()
        let watchlist = watchlist(recorder)
        try await watchlist.load()
        let target = ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs(tmdb: "10"))
        try await watchlist.set(true, target: target)

        try await watchlist.load(force: true)

        #expect(watchlist.contains(target) == false)
    }
}
