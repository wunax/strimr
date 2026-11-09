import MediaPlayer
@testable import Strimr
import Testing

struct NowPlayingItemTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")

    @Test func `an episode shows its series and number under the title`() throws {
        let media = MediaItem.make(
            id: "episode",
            server: server,
            title: "Pilot",
            type: .episode,
            seasonNumber: 1,
            episodeNumber: 3,
            seriesTitle: "Series",
        )

        let item = try #require(NowPlayingItem(
            media: media,
            artworkService: nil,
            skipBackwardSeconds: 10,
            skipForwardSeconds: 30,
        ))

        #expect(item.title == "Pilot")
        #expect(item.subtitle == "Series · \(String(localized: "media.labels.seasonEpisode \(1) \(3)"))")
        #expect(item.skipBackwardSeconds == 10)
        #expect(item.skipForwardSeconds == 30)
    }

    @Test func `an episode without series or number has no subtitle`() throws {
        let media = MediaItem.make(id: "episode", server: server, title: "Pilot", type: .episode)

        let item = try #require(NowPlayingItem(
            media: media,
            artworkService: nil,
            skipBackwardSeconds: 10,
            skipForwardSeconds: 10,
        ))

        #expect(item.subtitle == nil)
    }

    @Test func `a movie shows only its title`() throws {
        let media = MediaItem.make(id: "movie", server: server, title: "Movie", year: 2024)

        let item = try #require(NowPlayingItem(
            media: media,
            artworkService: nil,
            skipBackwardSeconds: 10,
            skipForwardSeconds: 10,
        ))

        #expect(item.title == "Movie")
        #expect(item.subtitle == nil)
    }

    @Test func `no media publishes nothing`() {
        #expect(NowPlayingItem(media: nil, artworkService: nil, skipBackwardSeconds: 10, skipForwardSeconds: 10) == nil)
    }

    @Test func `identity info leaves position and rate to the player`() {
        let item = NowPlayingItem(title: "Movie", subtitle: "Series", skipBackwardSeconds: 10, skipForwardSeconds: 10)

        let info = item.identityInfo(artwork: nil, isLive: true)

        #expect(info[MPMediaItemPropertyTitle] as? String == "Movie")
        #expect(info[MPMediaItemPropertyArtist] as? String == "Series")
        #expect(info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] == nil)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] == nil)
    }

    @Test func `the card only advances while playing and not buffering`() {
        #expect(NowPlayingPlayback.rate(isPlaying: true, isBuffering: false, requestedRate: 1.5) == 1.5)
        #expect(NowPlayingPlayback.rate(isPlaying: true, isBuffering: true, requestedRate: 1.5) == 0)
        #expect(NowPlayingPlayback.rate(isPlaying: false, isBuffering: false, requestedRate: 1.5) == 0)
        #expect(NowPlayingPlayback.rate(isPlaying: true, isBuffering: false, requestedRate: 0) == 1)
    }

    @Test func `a jump away from the extrapolated position is republished`() {
        #expect(!NowPlayingPlayback.hasDrifted(
            position: 105,
            publishedElapsed: 100,
            publishedRate: 1,
            secondsSincePublish: 5,
        ))
        #expect(NowPlayingPlayback.hasDrifted(
            position: 300,
            publishedElapsed: 100,
            publishedRate: 1,
            secondsSincePublish: 5,
        ))
        #expect(NowPlayingPlayback.hasDrifted(
            position: 110,
            publishedElapsed: 100,
            publishedRate: 0,
            secondsSincePublish: 5,
        ))
    }
}
