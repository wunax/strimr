@testable import Strimr
import Testing

struct LiveTVModelsTests {
    private func channel(_ id: String, _ title: String, number: String?, favorite: Bool = false) -> LiveTVChannel {
        LiveTVChannel(
            providerID: id,
            title: title,
            callSign: nil,
            number: number,
            thumbPath: nil,
            artPath: nil,
            lineupID: nil,
            dvrID: nil,
            isHD: false,
            isFavorite: favorite,
        )
    }

    @Test func `channel numbers read subchannels written with a dot or a dash`() {
        #expect(LiveTVChannelNumber("7") == LiveTVChannelNumber(major: 7))
        #expect(LiveTVChannelNumber("10.1") == LiveTVChannelNumber(major: 10, minor: 1))
        #expect(LiveTVChannelNumber(" 10-2 ") == LiveTVChannelNumber(major: 10, minor: 2))
        #expect(LiveTVChannelNumber("") == nil)
        #expect(LiveTVChannelNumber("HD") == nil)
    }

    @Test func `channel numbers compare numerically with the main channel before its subchannels`() throws {
        #expect(try #require(LiveTVChannelNumber("9")) < #require(LiveTVChannelNumber("10")))
        #expect(try #require(LiveTVChannelNumber("10")) < #require(LiveTVChannelNumber("10.1")))
        #expect(try #require(LiveTVChannelNumber("10.2")) < #require(LiveTVChannelNumber("10.10")))
    }

    @Test func `sorting by number puts channels without a number last, by name`() {
        let channels = [
            channel("a", "Zeta", number: nil),
            channel("b", "Beta", number: "10.1"),
            channel("c", "Alpha", number: nil),
            channel("d", "Delta", number: "2", favorite: true),
            channel("e", "Gamma", number: "10"),
        ]

        let sorted = LiveTVChannelSort.number.sorted(channels).map(\.providerID)

        #expect(sorted == ["d", "e", "b", "c", "a"])
    }

    @Test func `sorting by name ignores the number and favorites`() {
        let channels = [
            channel("a", "Canal 2", number: "1"),
            channel("b", "Canal 10", number: "2", favorite: true),
            channel("c", "beta", number: "3"),
        ]

        let sorted = LiveTVChannelSort.name.sorted(channels).map(\.providerID)

        #expect(sorted == ["c", "a", "b"])
    }
}
