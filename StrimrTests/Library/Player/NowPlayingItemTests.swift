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

    @Test func `identity info carries the extra details when present`() {
        var item = NowPlayingItem(title: "Pilot", skipBackwardSeconds: 10, skipForwardSeconds: 10)
        item.details = NowPlayingDetails(
            contentIdentifier: "42",
            queueIndex: 2,
            queueCount: 10,
            chapterCount: 8,
            intro: 30 ... 90,
            credits: 2400 ... 2500,
            nextTitle: "Second",
        )

        let info = item.identityInfo(artwork: nil, isLive: false, chapterNumber: 3)

        #expect(info[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String == "42")
        #expect(info[MPNowPlayingInfoPropertyPlaybackQueueIndex] as? Int == 2)
        #expect(info[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 10)
        #expect(info[MPNowPlayingInfoPropertyChapterCount] as? Int == 8)
        #expect(info[MPNowPlayingInfoPropertyChapterNumber] as? Int == 3)
        #expect(info["strimr.intro"] as? [Double] == [30, 90])
        #expect(info["strimr.credits"] as? [Double] == [2400, 2500])
        #expect(info["strimr.nextTitle"] as? String == "Second")
    }

    @Test func `identity info without details adds nothing`() {
        let info = NowPlayingItem(title: "Pilot", skipBackwardSeconds: 10, skipForwardSeconds: 10)
            .identityInfo(artwork: nil, isLive: false)

        #expect(info[MPNowPlayingInfoPropertyChapterCount] == nil)
        #expect(info[MPNowPlayingInfoPropertyPlaybackQueueCount] == nil)
        #expect(info["strimr.nextTitle"] == nil)
    }

    @Test func `finds the chapter holding a time, counting from one`() {
        func chapter(_ index: Int, _ start: Double, _ end: Double) -> MediaChapter {
            MediaChapter(
                id: "\(index)",
                title: "",
                index: index,
                startTime: start,
                endTime: end,
                image: nil,
                thumbPath: nil,
            )
        }
        let chapters = [chapter(0, 0, 100), chapter(1, 100, 200)]

        #expect(NowPlayingDetails.chapterNumber(at: 50, in: chapters) == 1)
        #expect(NowPlayingDetails.chapterNumber(at: 150, in: chapters) == 2)
        #expect(NowPlayingDetails.chapterNumber(at: 500, in: chapters) == nil)
        #expect(NowPlayingDetails.chapterNumber(at: 5, in: []) == nil)
    }
}
