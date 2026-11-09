@testable import Strimr
import Testing

@MainActor
struct PlexLiveTVCategoryTests {
    @Test func `maps guide entry types to categories`() {
        #expect(PlexLiveTVQuery.categories(metadataType: "movie") == [.movie])
        #expect(PlexLiveTVQuery.categories(metadataType: "episode") == [.series])
        #expect(PlexLiveTVQuery.categories(metadataType: "clip").isEmpty)
        #expect(PlexLiveTVQuery.categories(metadataType: nil).isEmpty)
    }

    @Test func `maps server hubs to categories`() {
        #expect(LiveTVCategory(sectionID: "sports") == .sports)
        #expect(LiveTVCategory(sectionID: "movies") == .movie)
        #expect(LiveTVCategory(sectionID: "now") == nil)
    }
}
