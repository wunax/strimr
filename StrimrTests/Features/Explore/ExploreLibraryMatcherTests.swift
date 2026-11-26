import Foundation
@testable import Strimr
import Testing

@MainActor
struct ExploreLibraryMatcherTests {
    private let server = ServerIdentity(provider: .plex, id: "server")

    private final class Lookups {
        var count = 0
        var results: [ExploreLibraryMatch] = []
    }

    private func matcher(
        _ lookups: Lookups,
        now: @escaping () -> Date,
        scope: @escaping () -> Set<ServerIdentity>,
    ) -> ExploreLibraryMatcher {
        ExploreLibraryMatcher(
            lookup: { _ in
                lookups.count += 1
                return lookups.results.isEmpty ? ExploreLibraryMatch(copies: [], uncheckedServers: 0)
                    : lookups.results.removeFirst()
            },
            scope: scope,
            now: now,
        )
    }

    private func copy() -> MediaCopy {
        MediaCopy(media: .make(id: "1", server: server), serverName: "Server", isReachable: true)
    }

    @Test func `a found title is kept for the session`() async {
        let lookups = Lookups()
        lookups.results = [ExploreLibraryMatch(copies: [copy()], uncheckedServers: 0)]
        var now = Date(timeIntervalSince1970: 0)
        let matcher = matcher(lookups, now: { now }, scope: { [server] })

        _ = await matcher.match(.make())
        now = now.addingTimeInterval(24 * 60 * 60)
        let match = await matcher.match(.make())

        #expect(lookups.count == 1)
        #expect(match.copies.count == 1)
    }

    @Test func `a title not found is searched again once the answer expired`() async {
        let lookups = Lookups()
        var now = Date(timeIntervalSince1970: 0)
        let matcher = matcher(lookups, now: { now }, scope: { [server] })

        _ = await matcher.match(.make())
        now = now.addingTimeInterval(ExploreLibraryMatcher.negativeLifetime - 1)
        _ = await matcher.match(.make())
        #expect(lookups.count == 1)

        now = now.addingTimeInterval(2)
        _ = await matcher.match(.make())
        #expect(lookups.count == 2)
    }

    @Test func `an answer a server sat out is never kept`() async {
        let lookups = Lookups()
        lookups.results = [ExploreLibraryMatch(copies: [], uncheckedServers: 1)]
        let matcher = matcher(lookups, now: { Date(timeIntervalSince1970: 0) }, scope: { [server] })

        let first = await matcher.match(.make())
        _ = await matcher.match(.make())

        #expect(first.uncheckedServers == 1)
        #expect(lookups.count == 2)
    }

    @Test func `a change in the servers searches again`() async {
        let lookups = Lookups()
        lookups.results = [ExploreLibraryMatch(copies: [copy()], uncheckedServers: 0)]
        var servers: Set<ServerIdentity> = [server]
        let matcher = matcher(lookups, now: { Date(timeIntervalSince1970: 0) }, scope: { servers })

        _ = await matcher.match(.make())
        servers.insert(ServerIdentity(provider: .jellyfin, id: "other"))
        _ = await matcher.match(.make())

        #expect(lookups.count == 2)
    }

    @Test func `ids learned from the details make a new search`() async {
        let lookups = Lookups()
        let matcher = matcher(lookups, now: { Date(timeIntervalSince1970: 0) }, scope: { [server] })

        _ = await matcher.match(.make(source: .plex, externalIDs: ExternalIDs(), plexGuid: "plex://movie/abc"))
        _ = await matcher.match(.make(
            source: .plex,
            externalIDs: ExternalIDs(tmdb: "100"),
            plexGuid: "plex://movie/abc",
        ))

        #expect(lookups.count == 2)
    }

    @Test func `a copy counts only when its ids match`() {
        let item = ExploreItem.make(kind: .movie, externalIDs: ExternalIDs(imdb: "tt1"))

        #expect(ExploreLibraryMatcher.matches(
            .make(id: "1", server: server, type: .movie, externalIDs: ExternalIDs(imdb: "tt1")),
            item: item,
        ))
        #expect(!ExploreLibraryMatcher.matches(
            .make(id: "2", server: server, type: .movie, externalIDs: ExternalIDs(imdb: "tt2")),
            item: item,
        ))
        #expect(!ExploreLibraryMatcher.matches(
            .make(id: "3", server: server, type: .series, externalIDs: ExternalIDs(imdb: "tt1")),
            item: item,
        ))
    }

    @Test func `a Plex Discover title matches a Plex server item on its guid alone`() {
        let item = ExploreItem.make(
            source: .plex,
            externalIDs: ExternalIDs(),
            plexGuid: "plex://movie/5d7768aaaaaaaaaaaaaaaaaa",
        )

        #expect(ExploreLibraryMatcher.matches(
            .make(id: "1", server: server, type: .movie, guid: "plex://movie/5d7768aaaaaaaaaaaaaaaaaa"),
            item: item,
        ))
    }

    @Test func `the original title is searched too when it differs`() {
        #expect(ExploreLibraryMatcher.titles(of: .make(title: "Amélie", originalTitle: "Le Fabuleux Destin"))
            == ["Amélie", "Le Fabuleux Destin"])
        #expect(ExploreLibraryMatcher.titles(of: .make(title: "Heat", originalTitle: "heat")) == ["Heat"])
    }
}
