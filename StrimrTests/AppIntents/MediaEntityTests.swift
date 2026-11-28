@testable import Strimr
import Testing

@MainActor
struct MediaEntityTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-b")

    @Test func `an entity id names its item and server`() {
        let media = MediaItem.make(id: "abc/def", server: server, title: "Heat", type: .movie, year: 1995)
        let entity = MediaEntity(media: media)
        #expect(entity.identity == media.identity)
        #expect(entity.kind == .movie)
        #expect(entity.subtitle == "1995")
    }

    @Test func `intents build the link of their item`() {
        let media = MediaItem.make(id: "42", server: server, type: .series)
        let entity = MediaEntity(media: media)
        #expect(entity.link { .play($0, mode: .shuffle) } == DeepLink(.play(
            .item(media.identity, kind: .series),
            mode: .shuffle,
        )))
    }

    @Test func `channel entities keep their link`() {
        let channel = LiveTVChannel(
            providerID: "ch-1",
            title: "Arte",
            callSign: nil,
            number: "7",
            thumbPath: nil,
            artPath: nil,
            lineupID: nil,
            dvrID: nil,
            isHD: false,
            isFavorite: false,
        )
        let entity = LiveChannelEntity(channel: channel, server: server)
        #expect(entity.link == DeepLink(.liveChannel("ch-1", server: server)))
        #expect(entity.name == "Arte")
    }

    @Test func `library entities keep their link`() {
        let library = Library(id: "3", title: "Films", type: .movie, server: server)
        let entity = LibraryEntity(library: library, serverName: "Home")
        #expect(entity.link == DeepLink(.library(library.identity)))
        #expect(entity.title == "Films")
    }
}
