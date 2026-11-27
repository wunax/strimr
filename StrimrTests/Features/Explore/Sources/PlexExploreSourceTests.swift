import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlexExploreSourceTests {
    @Test func `Discover metadata maps movies and shows with their guids`() throws {
        let container = try Fixtures.decode(PlexDiscoverContainerResponse.self, from: "plex-discover-watchlist")
            .mediaContainer
        let items = container.metadata.compactMap(PlexExploreSource.item)

        #expect(items.map(\.title) == ["Sample Movie", "Sample Show"])
        let movie = try #require(items.first)
        #expect(movie.source == .plex)
        #expect(movie.sourceID == "5d7768aaaaaaaaaaaaaaaaaa")
        #expect(movie.plexGuid == "plex://movie/5d7768aaaaaaaaaaaaaaaaaa")
        #expect(movie.originalTitle == "Film Exemple")
        #expect(movie.externalIDs == ExternalIDs(imdb: "tt0000001", tmdb: "2001"))
        #expect(movie.posterURL?.absoluteString == "https://images.example.invalid/movie-poster.jpg")
        #expect(container.totalSize == 2)
    }

    @Test func `a title without a guid gets the one its rating key makes`() throws {
        let container = try Fixtures.decode(PlexDiscoverContainerResponse.self, from: "plex-discover-search")
            .mediaContainer
        let items = container.searchResults.flatMap(\.results).compactMap(\.metadata).compactMap(PlexExploreSource.item)

        #expect(items.map(\.title) == ["Searched Movie", "Searched Show"])
        #expect(items.last?.plexGuid == "plex://show/5d7768eeeeeeeeeeeeeeeeee")
    }

    @Test func `the watchlist knows a Plex server item by its guid`() throws {
        let item = try #require(Fixtures.decode(PlexDiscoverContainerResponse.self, from: "plex-discover-watchlist")
            .mediaContainer.metadata.first.flatMap(PlexExploreSource.item))
        let target = ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs(), sourceID: item.sourceID)

        #expect(!item.watchlistTarget.keys.isDisjoint(with: target.keys))
    }
}
