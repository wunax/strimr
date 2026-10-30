@testable import Strimr
import Testing

struct PlaybackQueueTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server")
    private var episodes: [MediaItem] {
        (1 ... 6).map { MediaItem.make(id: "episode-\($0)", server: server, type: .episode) }
    }

    @Test func `keeps the episodes before the starting one`() {
        let queue = PlaybackQueue(media: episodes, startingAt: "episode-4", shuffle: false)

        #expect(queue.items.map(\.media.id) == episodes.map(\.id))
        #expect(queue.currentIndex == 3)
    }

    @Test func `starts at the first item when the start is unknown`() {
        let queue = PlaybackQueue(media: episodes, startingAt: "series", shuffle: false)

        #expect(queue.currentIndex == 0)
    }

    @Test func `shuffled queue plays the start first and drops what precedes it`() {
        let queue = PlaybackQueue(media: episodes, startingAt: "episode-3", shuffle: true)
        let ids = queue.items.map(\.media.id)

        #expect(queue.currentIndex == 0)
        #expect(ids.first == "episode-3")
        #expect(Set(ids) == ["episode-3", "episode-4", "episode-5", "episode-6"])
    }

    @Test func `shuffled queue without a start keeps every item`() {
        let queue = PlaybackQueue(media: episodes, startingAt: nil, shuffle: true)

        #expect(queue.currentIndex == 0)
        #expect(Set(queue.items.map(\.media.id)) == Set(episodes.map(\.id)))
    }
}
