import AetherEngine
import Foundation
@testable import Strimr
import Testing

struct PlexExternalPlaybackTests {
    private let baseURL = URL(string: "https://plex.example.com:32400")!

    @Test func `uses the part of the default version with the token in the query`() throws {
        let url = try externalURL(itemIndex: 0, version: .automatic)

        #expect(url?
            .absoluteString ==
            "https://plex.example.com:32400/library/parts/301/1700000000/file.mkv?X-Plex-Token=test-token")
    }

    @Test func `uses the part of the requested version`() throws {
        let url = try externalURL(itemIndex: 0, version: .explicit(versionID: "202"))

        #expect(url?
            .absoluteString ==
            "https://plex.example.com:32400/library/parts/302/1700000001/file.mp4?X-Plex-Token=test-token")
    }

    @Test func `has no URL when the file is missing`() throws {
        #expect(try externalURL(itemIndex: 1, version: .automatic) == nil)
    }

    @Test func `sends the SRT sidecars only, server selection first`() throws {
        let container = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-movie-versions")
        let item = try #require(container.mediaContainer.metadata?.first)
        let urls = PlexMediaServiceAdapter.externalSubtitleURLs(
            in: item.media ?? [],
            version: .automatic,
            baseURL: baseURL,
            token: "test-token",
        )

        #expect(urls.map(\.absoluteString) == [
            "https://plex.example.com:32400/library/streams/404?X-Plex-Token=test-token",
            "https://plex.example.com:32400/library/streams/403?X-Plex-Token=test-token",
        ])
    }

    @Test func `has no subtitles for a version without sidecars`() throws {
        let container = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-movie-versions")
        let item = try #require(container.mediaContainer.metadata?.first)

        #expect(PlexMediaServiceAdapter.externalSubtitleURLs(
            in: item.media ?? [],
            version: .explicit(versionID: "202"),
            baseURL: baseURL,
            token: "test-token",
        ).isEmpty)
    }

    @Test func `ties player sidecars to their Plex stream ids`() throws {
        let container = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-movie-versions")
        let item = try #require(container.mediaContainer.metadata?.first)
        let streams = try #require(item.media?.first?.parts.first?.stream)
        let subtitles = PlexMediaServiceAdapter.externalSubtitles(in: streams) {
            MediaRepository.mediaURL(path: $0, baseURL: baseURL, token: "test-token")
        }

        #expect(subtitles.map(\.providerStreamID) == [403, 404, 405])
        #expect(subtitles.map(\.track.url.absoluteString) == [
            "https://plex.example.com:32400/library/streams/403?X-Plex-Token=test-token",
            "https://plex.example.com:32400/library/streams/404?X-Plex-Token=test-token",
            "https://plex.example.com:32400/library/streams/405?X-Plex-Token=test-token",
        ])
    }

    private func externalURL(itemIndex: Int, version: MediaVersionRequest) throws -> URL? {
        let container = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-movie-versions")
        let item = try #require(container.mediaContainer.metadata?[itemIndex])
        return PlexMediaServiceAdapter.externalPlaybackURL(
            in: item.media ?? [],
            version: version,
            baseURL: baseURL,
            token: "test-token",
        )
    }
}
