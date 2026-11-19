import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlexLiveTVChannelTests {
    private func lineupChannels() throws -> [LiveTVChannel] {
        let root = try #require(JSONSerialization
            .jsonObject(with: Fixtures.data("plex-livetv-lineup-channels")) as? [String: Any])
        let container = try #require(root["MediaContainer"] as? [String: Any])
        let items = try #require(container["Channel"] as? [[String: Any]])
        return items.compactMap { PlexLiveTVService.channel(from: $0, lineupID: "lineup", dvrID: "dvr") }
    }

    @Test func `reads the channel number and HD flag of lineup channels`() throws {
        let channels = try lineupChannels()
        #expect(channels.map(\.number) == ["001", "012"])
        #expect(channels.map(\.isHD) == [true, false])
    }

    @Test func `sorts lineup channels by number or by name`() throws {
        let channels = try lineupChannels()
        #expect(LiveTVChannelSort.number.sorted(channels).map(\.providerID) == ["channel-one", "channel-two"])
        #expect(LiveTVChannelSort.name.sorted(channels).map(\.providerID) == ["channel-two", "channel-one"])
    }
}
