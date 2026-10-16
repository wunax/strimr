import Foundation
@testable import Strimr
import Testing

struct JellyfinExternalPlaybackTests {
    private let baseURL = URL(string: "https://jellyfin.example.com/jellyfin")!

    @Test func `streams the default source statically with the token`() throws {
        let url = try externalURL(version: .automatic)

        #expect(url
            .absoluteString ==
            "https://jellyfin.example.com/jellyfin/Videos/movie-1/stream.mkv?Static=true&MediaSourceId=source-1&api_key=test-token")
    }

    @Test func `streams the requested source with its container extension`() throws {
        let url = try externalURL(version: .explicit(versionID: "source-2"))

        #expect(url
            .absoluteString ==
            "https://jellyfin.example.com/jellyfin/Videos/movie-1/stream.mov?Static=true&MediaSourceId=source-2&api_key=test-token")
    }

    @Test func `fails without a media source`() throws {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-movie")

        #expect(throws: ExternalPlaybackError.noPlayableSource) {
            try JellyfinMediaServiceAdapter.externalPlaybackURL(
                item: item,
                version: .automatic,
                baseURL: baseURL,
                token: "test-token",
            )
        }
    }

    @Test func `sends external text subtitles as SRT, source default first`() throws {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-movie-versions")
        let urls = try JellyfinMediaServiceAdapter.externalSubtitleURLs(
            item: item,
            version: .automatic,
            baseURL: baseURL,
            token: "test-token",
        )

        #expect(urls.map(\.absoluteString) == [
            "https://jellyfin.example.com/jellyfin/Videos/movie-1/source-1/Subtitles/3/0/Stream.srt?api_key=test-token",
            "https://jellyfin.example.com/jellyfin/Videos/movie-1/source-1/Subtitles/2/0/Stream.srt?api_key=test-token",
        ])
    }

    @Test func `has no subtitles for a source without external ones`() throws {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-movie-versions")

        #expect(try JellyfinMediaServiceAdapter.externalSubtitleURLs(
            item: item,
            version: .explicit(versionID: "source-2"),
            baseURL: baseURL,
            token: "test-token",
        ).isEmpty)
    }

    private func externalURL(version: MediaVersionRequest) throws -> URL {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-movie-versions")
        return try JellyfinMediaServiceAdapter.externalPlaybackURL(
            item: item,
            version: version,
            baseURL: baseURL,
            token: "test-token",
        )
    }
}
