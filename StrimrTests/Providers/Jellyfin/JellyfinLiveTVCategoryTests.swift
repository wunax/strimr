import Foundation
@testable import Strimr
import Testing

@MainActor
struct JellyfinLiveTVCategoryTests {
    @Test func `maps program flags to categories`() throws {
        let result = try Fixtures.decode(
            JellyfinQueryResult<JellyfinLiveProgramDTO>.self,
            from: "jellyfin-live-programs",
        )

        #expect(result.items.map(\.categories) == [[.sports], [.movie, .kids], [.series]])
    }
}
