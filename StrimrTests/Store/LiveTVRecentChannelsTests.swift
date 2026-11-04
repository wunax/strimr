import Foundation
@testable import Strimr
import Testing

@MainActor
struct LiveTVRecentChannelsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "LiveTVRecentChannelsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func `moves a channel watched again to the front`() {
        #expect(LiveTVRecentChannels.inserting("b", into: ["a", "b", "c"]) == ["b", "a", "c"])
    }

    @Test func `keeps ten channels`() {
        let keys = (0 ..< 10).map(String.init)
        #expect(LiveTVRecentChannels.inserting("new", into: keys) == ["new"] + keys.prefix(9))
    }

    @Test func `keeps each server apart`() {
        let defaults = makeDefaults()
        let plex = LiveTVRecentChannels(
            server: ServerIdentity(provider: .plex, id: "a"),
            userID: "user",
            defaults: defaults,
        )
        let jellyfin = LiveTVRecentChannels(
            server: ServerIdentity(provider: .jellyfin, id: "a"),
            userID: "user",
            defaults: defaults,
        )

        plex.record(LiveTVChannelIdentity(providerID: "1", lineupID: "lineup", dvrID: "dvr"))

        #expect(plex.channelKeys == ["1|lineup|dvr"])
        #expect(jellyfin.channelKeys.isEmpty)
    }

    @Test func `keeps each user of a server apart`() {
        let defaults = makeDefaults()
        let server = ServerIdentity(provider: .plex, id: "a")
        let parent = LiveTVRecentChannels(server: server, userID: "parent", defaults: defaults)
        let child = LiveTVRecentChannels(server: server, userID: "child", defaults: defaults)

        parent.record(LiveTVChannelIdentity(providerID: "1", lineupID: "lineup", dvrID: "dvr"))

        #expect(parent.channelKeys == ["1|lineup|dvr"])
        #expect(child.channelKeys.isEmpty)
    }
}
