import Foundation
@testable import Strimr
import Testing

struct SeerrTrailerTests {
    private static let serverURL = URL(string: "https://seerr.example.com")

    @Test func `picks the largest openable trailer and ignores teasers`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie-videos")

        #expect(media
            .trailerURL(youtubeBaseURL: nil, serverURL: Self.serverURL) ==
            URL(string: "https://www.youtube.com/watch?v=largeKey"))
    }

    @Test func `youtube trailer uses the instance youtube url override`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie-videos")

        #expect(
            media.trailerURL(youtubeBaseURL: "https://yt.example.com/watch?v=", serverURL: Self.serverURL)
                == URL(string: "https://yt.example.com/watch?v=largeKey"),
        )
    }

    @Test func `protocol relative youtube url override takes the server scheme`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie-videos")

        #expect(
            media.trailerURL(youtubeBaseURL: "//yt.example.com/watch?v=", serverURL: Self.serverURL)
                == URL(string: "https://yt.example.com/watch?v=largeKey"),
        )
    }

    @Test func `unresolvable youtube url override falls back to the video url`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie-videos")

        #expect(
            media.trailerURL(youtubeBaseURL: "//yt.example.com/watch?v=", serverURL: nil)
                == URL(string: "https://www.youtube.com/watch?v=largeKey"),
        )
    }

    @Test func `empty youtube url override falls back to the video url`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie-videos")

        #expect(media
            .trailerURL(youtubeBaseURL: "", serverURL: Self.serverURL) ==
            URL(string: "https://www.youtube.com/watch?v=largeKey"))
    }

    @Test func `media without trailers has no trailer url`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie")

        #expect(media.trailerURL(youtubeBaseURL: nil, serverURL: Self.serverURL) == nil)
    }
}
