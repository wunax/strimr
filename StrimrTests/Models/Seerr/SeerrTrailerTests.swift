import Foundation
@testable import Strimr
import Testing

struct SeerrTrailerTests {
    @Test func `picks the largest trailer and ignores teasers`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie-videos")

        #expect(media.trailerURL(youtubeBaseURL: nil) == URL(string: "https://www.youtube.com/watch?v=largeKey"))
    }

    @Test func `youtube trailer uses the instance youtube url override`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie-videos")

        #expect(
            media.trailerURL(youtubeBaseURL: "https://yt.example.com/watch?v=")
                == URL(string: "https://yt.example.com/watch?v=largeKey"),
        )
    }

    @Test func `empty youtube url override falls back to the video url`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie-videos")

        #expect(media.trailerURL(youtubeBaseURL: "") == URL(string: "https://www.youtube.com/watch?v=largeKey"))
    }

    @Test func `media without trailers has no trailer url`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie")

        #expect(media.trailerURL(youtubeBaseURL: nil) == nil)
    }
}
