import Foundation
@testable import Strimr
import Testing

struct MediaMatchingTests {
    private let plexA = ServerIdentity(provider: .plex, id: "server-a")
    private let jellyfin = ServerIdentity(provider: .jellyfin, id: "server-c")

    @Test func `plex guids map to external ids`() throws {
        let hub = try #require(
            Fixtures.decode(PlexHubMediaContainer.self, from: "plex-continue-watching").mediaContainer.hub?.first,
        )
        let items = (hub.metadata ?? []).map { MediaItem(plexItem: $0, server: plexA) }

        #expect(items[0].externalIDs == ExternalIDs(imdb: "tt0000001", tmdb: "1001", tvdb: "2001"))
        #expect(items[1].externalIDs == ExternalIDs(imdb: "tt0000002", tvdb: "3001"))
    }

    @Test func `jellyfin provider ids map to external ids`() throws {
        let items = try Fixtures.decode(JellyfinQueryResult<JellyfinItem>.self, from: "jellyfin-resume").items
            .map { MediaItem(jellyfinItem: $0, server: jellyfin) }

        #expect(items[0].externalIDs == ExternalIDs(imdb: "tt0000001", tmdb: "1001"))
        #expect(items[1].externalIDs == ExternalIDs(tvdb: "3001"))
        #expect(items[2].externalIDs.isEmpty)
    }

    @Test func `plex copies match by guid`() {
        let lhs = descriptor(.movie, guid: "plex://movie/abc")
        let rhs = descriptor(.movie, guid: "PLEX://movie/abc")

        #expect(MediaMatching.matches(lhs, rhs))
    }

    @Test func `local guids never match`() {
        let lhs = descriptor(.movie, guid: "local://12")
        let rhs = descriptor(.movie, guid: "local://12")

        #expect(!MediaMatching.matches(lhs, rhs))
        #expect(!MediaMatching.matches(
            descriptor(.movie, guid: "com.plexapp.agents.none://1"),
            descriptor(.movie, guid: "com.plexapp.agents.none://1"),
        ))
    }

    @Test func `plex and jellyfin copies match by external ids`() throws {
        let plex = try #require(
            Fixtures.decode(PlexHubMediaContainer.self, from: "plex-continue-watching").mediaContainer.hub?.first,
        ).metadata?.map { MediaItem(plexItem: $0, server: plexA) } ?? []
        let jellyfinItems = try Fixtures.decode(JellyfinQueryResult<JellyfinItem>.self, from: "jellyfin-resume").items
            .map { MediaItem(jellyfinItem: $0, server: jellyfin) }

        #expect(MediaMatching.matches(plex[0].matchDescriptor, jellyfinItems[0].matchDescriptor))
        #expect(MediaMatching.matches(plex[1].matchDescriptor, jellyfinItems[1].matchDescriptor))
        #expect(!MediaMatching.matches(plex[0].matchDescriptor, jellyfinItems[1].matchDescriptor))
    }

    @Test func `tmdb ids of movies and shows do not collide`() {
        let movie = descriptor(.movie, ids: ExternalIDs(tmdb: "42"))
        let series = descriptor(.series, ids: ExternalIDs(tmdb: "42"))

        #expect(!MediaMatching.matches(movie, series))
    }

    @Test func `episodes also compare season and episode numbers`() {
        let first = descriptor(.episode, ids: ExternalIDs(tvdb: "500"), season: 1, episode: 1)
        let same = descriptor(.episode, ids: ExternalIDs(tvdb: "500"), season: 1, episode: 1)
        let next = descriptor(.episode, ids: ExternalIDs(tvdb: "500"), season: 1, episode: 2)
        let unnumbered = descriptor(.episode, ids: ExternalIDs(tvdb: "500"))

        #expect(MediaMatching.matches(first, same))
        #expect(!MediaMatching.matches(first, next))
        #expect(!MediaMatching.matches(first, unnumbered))
    }

    @Test func `items without ids stay apart even with the same title`() {
        let groups = MediaMatching.group(["a", "b"]) { _ in descriptor(.movie) }

        #expect(groups == [["a"], ["b"]])
    }

    @Test func `grouping is transitive and keeps the order`() {
        let descriptors: [String: MediaMatchDescriptor] = [
            "plex-a": descriptor(.movie, guid: "plex://movie/1"),
            "other": descriptor(.movie, ids: ExternalIDs(imdb: "tt9")),
            "plex-b": descriptor(.movie, guid: "plex://movie/1", ids: ExternalIDs(tmdb: "7")),
            "jellyfin": descriptor(.movie, ids: ExternalIDs(tmdb: "7")),
        ]
        let order = ["plex-a", "other", "plex-b", "jellyfin"]

        let groups = MediaMatching.group(order) { descriptors[$0]! }

        #expect(groups == [["plex-a", "plex-b", "jellyfin"], ["other"]])
    }

    @Test func `plex editions of a title do not match each other`() {
        let ids = ExternalIDs(imdb: "tt1")
        let standard = descriptor(.series, guid: "plex://show/abc", ids: ids)
        let edition = descriptor(.series, guid: "plex://show/abc", ids: ids, edition: "Black and White")

        #expect(!MediaMatching.matches(standard, edition))
        #expect(MediaMatching.matches(
            edition,
            descriptor(.series, guid: "plex://show/abc", ids: ids, edition: " black and white "),
        ))
        #expect(MediaMatching.matches(standard, descriptor(.series, guid: "plex://show/abc", ids: ids, edition: " ")))
    }

    @Test func `plex editions stay apart when grouping`() throws {
        let items = try (Fixtures.decode(PlexItemMediaContainer.self, from: "plex-section-editions")
            .mediaContainer.metadata ?? []).map { MediaItem(plexItem: $0, server: plexA) }

        #expect(MediaMatching.group(items) { $0.matchDescriptor }.count == 2)
    }

    private func descriptor(
        _ kind: MediaMatchDescriptor.Kind,
        guid: String? = nil,
        ids: ExternalIDs = ExternalIDs(),
        season: Int? = nil,
        episode: Int? = nil,
        edition: String? = nil,
    ) -> MediaMatchDescriptor {
        MediaMatchDescriptor(
            kind: kind,
            guid: guid,
            externalIDs: ids,
            seasonNumber: season,
            episodeNumber: episode,
            edition: edition,
        )
    }
}
