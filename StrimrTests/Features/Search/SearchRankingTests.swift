import Foundation
@testable import Strimr
import Testing

@MainActor
struct SearchRankingTests {
    private let plexA = ServerIdentity(provider: .plex, id: "a")
    private let plexB = ServerIdentity(provider: .plex, id: "b")
    private let jellyfin = ServerIdentity(provider: .jellyfin, id: "c")

    @Test func `copies on several servers become one result`() {
        let sources = [
            source(MediaItem.make(id: "1", server: plexA, title: "Alien", guid: "plex://movie/x"), "A"),
            source(MediaItem.make(id: "2", server: plexB, title: "Alien", guid: "plex://movie/x"), "B"),
            source(
                MediaItem.make(id: "3", server: jellyfin, title: "Alien", externalIDs: ExternalIDs(imdb: "tt1")),
                "C",
            ),
            source(
                MediaItem.make(
                    id: "4",
                    server: plexB,
                    title: "Alien",
                    guid: "plex://movie/x",
                    externalIDs: ExternalIDs(imdb: "tt1"),
                ),
                "B",
            ),
        ]

        let results = SearchRanking.merge(sources, query: "alien")

        #expect(results.count == 1)
        #expect(results[0].serverNames == ["A", "B", "C", "B"])
    }

    @Test func `the same title without ids is not merged`() {
        let sources = [
            source(MediaItem.make(id: "1", server: plexA, title: "Home Video"), "A"),
            source(MediaItem.make(id: "2", server: jellyfin, title: "Home Video"), "C"),
        ]

        #expect(SearchRanking.merge(sources, query: "home").count == 2)
    }

    @Test func `results are ranked by relevance, then year, then title`() {
        let sources = [
            source(MediaItem.make(id: "1", server: plexA, title: "The Matrix Reloaded", year: 2003), "A"),
            source(MediaItem.make(id: "2", server: plexA, title: "Matrix", year: 1999), "A"),
            source(MediaItem.make(id: "3", server: jellyfin, title: "Matrix Resurrections", year: 2021), "C"),
            source(MediaItem.make(id: "4", server: jellyfin, title: "Matrix Revolutions", year: 2003), "C"),
            source(MediaItem.make(id: "5", server: plexA, title: "Matrix Reloaded", year: 2003), "A"),
        ]

        let titles = SearchRanking.merge(sources, query: "Matrix").map(\.media.primaryLabel)

        #expect(titles == [
            "Matrix",
            "Matrix Resurrections",
            "Matrix Reloaded",
            "Matrix Revolutions",
            "The Matrix Reloaded",
        ])
    }

    @Test func `relevance folds case and diacritics`() {
        let query = SearchRanking.normalize("Amelie")

        #expect(SearchRanking.relevance(of: "Amélie", query: query) == 0)
        #expect(SearchRanking.relevance(of: "AMÉLIE 2", query: query) == 1)
        #expect(SearchRanking.relevance(of: "Le fabuleux destin d'Amélie", query: query) == 2)
        #expect(SearchRanking.relevance(of: "Other", query: query) == 3)
    }

    private func source(_ item: MediaItem, _ serverName: String) -> SearchResultSource {
        SearchResultSource(server: item.identity.server, serverName: serverName, media: .playable(item))
    }
}
