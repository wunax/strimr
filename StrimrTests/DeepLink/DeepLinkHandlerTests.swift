import Foundation
@testable import Strimr
import Testing

@MainActor
struct DeepLinkHandlerTests {
    private let server = ServerIdentity(provider: .plex, id: "s1")

    private func channel(_ id: String, _ title: String, number: String?, callSign: String? = nil) -> LiveTVChannel {
        LiveTVChannel(
            providerID: id,
            title: title,
            callSign: callSign,
            number: number,
            thumbPath: nil,
            artPath: nil,
            lineupID: nil,
            dvrID: nil,
            isHD: false,
            isFavorite: false,
        )
    }

    @Test func `channels match by id, then number, call sign and title`() {
        let channels = [
            channel("101", "France 2", number: "2", callSign: "FR2"),
            channel("102", "TF1", number: "1"),
            channel("103", "Arte", number: "7", callSign: "ARTE"),
        ]
        #expect(DeepLinkHandler.channelIndex(matching: "103", in: channels) == 2)
        #expect(DeepLinkHandler.channelIndex(matching: "2", in: channels) == 0)
        #expect(DeepLinkHandler.channelIndex(matching: "fr2", in: channels) == 0)
        #expect(DeepLinkHandler.channelIndex(matching: "tf1", in: channels) == 1)
        #expect(DeepLinkHandler.channelIndex(matching: "M6", in: channels) == nil)
    }

    private func copy(_ id: String, offset: TimeInterval? = nil, reachable: Bool = true) -> MediaCopy {
        MediaCopy(
            media: MediaItem.make(id: id, server: server, viewOffset: offset),
            serverName: "Server",
            isReachable: reachable,
        )
    }

    @Test func `the copy furthest into is played`() {
        let copies = [copy("a"), copy("b", offset: 30), copy("c", offset: 600)]
        #expect(DeepLinkHandler.preferredCopy(copies)?.media.id == "c")
    }

    @Test func `otherwise the first reachable copy is played`() {
        let copies = [copy("a", offset: 900, reachable: false), copy("b"), copy("c")]
        #expect(DeepLinkHandler.preferredCopy(copies)?.media.id == "b")
        #expect(DeepLinkHandler.preferredCopy([copy("a", reachable: false)])?.media.id == "a")
        #expect(DeepLinkHandler.preferredCopy([]) == nil)
    }

    @Test func `catalog links search with their title and ids`() throws {
        let item = try #require(DeepLinkHandler.exploreItem(for: .init(
            kind: .show,
            ids: ExternalIDs(tvdb: "73739"),
            title: "Lost",
            year: 2004,
        )))
        #expect(item.kind == .show)
        #expect(item.title == "Lost")
        #expect(item.year == 2004)
        #expect(item.matchDescriptor.matchKeys == ["tvdb:series:73739"])
    }

    @Test func `a title alone never makes a copy`() throws {
        let item = try #require(DeepLinkHandler.exploreItem(for: .init(
            kind: .movie,
            ids: ExternalIDs(tmdb: "949"),
            title: "Heat",
        )))
        let sameTitle = MediaItem.make(id: "1", server: server, title: "Heat", externalIDs: ExternalIDs(tmdb: "1"))
        let sameID = MediaItem.make(
            id: "2",
            server: server,
            title: "Heat (1995)",
            externalIDs: ExternalIDs(tmdb: "949"),
        )
        #expect(!ExploreLibraryMatcher.matches(sameTitle, item: item))
        #expect(ExploreLibraryMatcher.matches(sameID, item: item))
    }
}
