@testable import Strimr
import Testing

struct ExploreSourceRegistryTests {
    @Test func `the user's pick wins while it is connected`() {
        #expect(ExploreSourceRegistry.resolveActive(preferred: .trakt, connected: [.seerr, .trakt]) == .trakt)
    }

    @Test func `Seerr comes first by default so the former Discover tab looks the same`() {
        #expect(ExploreSourceRegistry
            .resolveActive(preferred: nil, connected: [.simkl, .trakt, .plex, .seerr]) == .seerr)
        #expect(ExploreSourceRegistry.resolveActive(preferred: nil, connected: [.simkl, .trakt, .plex]) == .plex)
        #expect(ExploreSourceRegistry.resolveActive(preferred: nil, connected: [.simkl, .trakt]) == .trakt)
    }

    @Test func `a disconnected pick falls back to the priority order`() {
        #expect(ExploreSourceRegistry.resolveActive(preferred: .simkl, connected: [.plex, .trakt]) == .plex)
    }

    @Test func `no source leaves nothing active`() {
        #expect(ExploreSourceRegistry.resolveActive(preferred: .plex, connected: []) == nil)
    }

    @MainActor
    private final class StubSource: ExploreSource {
        let id: ExploreSourceID
        let rows: [ExploreRowID] = []
        let watchlist: ExploreWatchlist? = nil

        init(_ id: ExploreSourceID) {
            self.id = id
        }

        func fetchRow(_: ExploreRowID, page _: Int) async throws -> ExplorePage {
            ExplorePage(items: [])
        }

        func search(_: String) async throws -> [ExploreItem] {
            []
        }
    }

    @MainActor
    @Test func `a source whose key did not change is kept with its token`() async throws {
        let trakt = StubSource(.trakt)
        let previous = [ExploreSourceID.trakt: ExploreSourceRegistry.BuiltSource(source: trakt, key: "p1", token: 1)]

        let result = try #require(await ExploreSourceRegistry.rebuild(
            previous: previous,
            lastToken: 1,
            key: { $0 == .trakt ? "p1" : nil },
            build: { _ in Issue.record("nothing to build"); return nil },
        ))

        #expect(result.sources[.trakt]?.source === trakt)
        #expect(result.sources[.trakt]?.token == 1)
    }

    @MainActor
    @Test func `a source rebuilt for another profile gets a new token`() async throws {
        let previous = [
            ExploreSourceID.trakt: ExploreSourceRegistry.BuiltSource(source: StubSource(.trakt), key: "p1", token: 1),
        ]

        let result = try #require(await ExploreSourceRegistry.rebuild(
            previous: previous,
            lastToken: 1,
            key: { $0 == .trakt ? "p2" : nil },
            build: { StubSource($0) },
        ))

        #expect(result.sources[.trakt]?.token == 2)
        #expect(result.lastToken == 2)
    }

    @MainActor
    @Test func `a connected source that cannot be built is listed as failed`() async throws {
        let result = try #require(await ExploreSourceRegistry.rebuild(
            previous: [:],
            lastToken: 0,
            key: { $0 == .plex ? "p1" : nil },
            build: { _ in nil },
        ))

        #expect(result.sources.isEmpty)
        #expect(result.failed == [.plex])
    }

    @MainActor
    @Test func `a rebuild cancelled halfway returns nothing to commit`() async {
        let task = Task { @MainActor in
            await ExploreSourceRegistry.rebuild(
                previous: [:],
                lastToken: 0,
                key: { _ in "p2" },
                build: { id in
                    if id == .plex {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    return StubSource(id)
                },
            )
        }

        #expect(await task.value == nil)
    }
}
