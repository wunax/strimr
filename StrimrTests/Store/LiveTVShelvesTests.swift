import Foundation
@testable import Strimr
import Testing

@MainActor
struct LiveTVShelvesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func channel(_ id: String, favorite: Bool = false) -> LiveTVChannel {
        LiveTVChannel(
            providerID: id,
            title: "Channel \(id)",
            callSign: nil,
            number: id,
            thumbPath: nil,
            artPath: nil,
            lineupID: nil,
            dvrID: nil,
            isHD: true,
            isFavorite: favorite,
        )
    }

    private func program(
        _ id: String,
        on channel: LiveTVChannel,
        start: TimeInterval,
        minutes: TimeInterval = 60,
        title: String? = nil,
        categories: Set<LiveTVCategory> = [],
    ) -> LiveTVProgram {
        LiveTVProgram(
            id: id,
            channelID: channel.providerID,
            channelIdentity: channel.identity,
            title: title ?? "Program \(id)",
            seriesTitle: nil,
            summary: nil,
            startDate: now.addingTimeInterval(start * 60),
            endDate: now.addingTimeInterval((start + minutes) * 60),
            thumbPath: nil,
            artPath: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            isLive: false,
            isPremiere: false,
            recordingID: nil,
            seriesRecordingID: nil,
            recordingStatus: nil,
            providerGUID: nil,
            categories: categories,
        )
    }

    @Test func `orders rails and hides empty ones`() {
        let one = channel("1", favorite: true)
        let two = channel("2")
        let shelves = LiveTVShelves(
            channels: [one, two],
            programs: [program("a", on: one, start: -10), program("b", on: two, start: 30)],
            recentChannelKeys: [two.identity.storageKey],
            now: now,
        )

        #expect(shelves.shelves.map(\.kind) == [.recent, .favorites, .onNow, .upcoming])
        #expect(shelves.shelves[0].items.map(\.channel) == [two])
        #expect(shelves.shelves[0].items[0].program == nil)
        #expect(shelves.shelves[2].items.map(\.program?.id) == ["a"])
    }

    @Test func `upcoming keeps the next program within 90 minutes`() {
        let one = channel("1")
        let two = channel("2")
        let three = channel("3")
        let shelves = LiveTVShelves(
            channels: [one, two, three],
            programs: [
                program("late", on: one, start: 91),
                program("soon", on: two, start: 60),
                program("sooner", on: three, start: 10),
                program("after", on: three, start: 70),
            ],
            now: now,
        )

        let upcoming = shelves.shelves.first { $0.kind == .upcoming }
        #expect(upcoming?.items.map(\.program?.id) == ["sooner", "soon"])
    }

    @Test func `shows a category rail from three channels`() {
        let channels = (1 ... 4).map { channel(String($0)) }
        let sports = channels.prefix(3).map { program("s\($0.providerID)", on: $0, start: -5, categories: [.sports]) }
        let news = program("n", on: channels[3], start: -5, categories: [.news])

        let shelves = LiveTVShelves(channels: channels, programs: sports + [news], now: now)

        #expect(shelves.shelves.map(\.kind).contains(.category(.sports)))
        #expect(!shelves.shelves.map(\.kind).contains(.category(.news)))
    }

    @Test func `server hubs give categories to programs without any`() {
        let channels = (1 ... 3).map { channel(String($0)) }
        let programs = channels.map { program("k\($0.providerID)", on: $0, start: -5) }
        let section = LiveTVOnNowSection(id: "kids", title: "Kids", programs: programs)

        let shelves = LiveTVShelves(channels: channels, programs: programs, onNowSections: [section], now: now)

        #expect(shelves.shelves.map(\.kind).contains(.category(.kids)))
    }

    @Test func `lists a channel once per rail`() {
        let one = channel("1", favorite: true)
        let shelves = LiveTVShelves(
            channels: [one, one],
            programs: [program("a", on: one, start: -10)],
            recentChannelKeys: [one.identity.storageKey, one.identity.storageKey],
            now: now,
        )

        #expect(shelves.shelves.allSatisfy { $0.items.count == 1 })
    }

    @Test func `puts recordings in progress first`() {
        func recording(_ id: String, _ status: DVRRecordingStatus, start: TimeInterval) -> DVRRecording {
            DVRRecording(
                id: id,
                title: id,
                channelTitle: nil,
                startDate: now.addingTimeInterval(start),
                endDate: nil,
                status: status,
                programID: nil,
                playableMedia: nil,
                errorMessage: nil,
            )
        }
        let shelves = LiveTVShelves(
            channels: [],
            programs: [],
            recordings: [
                recording("later", .scheduled, start: 7200),
                recording("cancelled", .cancelled, start: 0),
                recording("now", .recording, start: -600),
                recording("soon", .scheduled, start: 600),
            ],
            now: now,
        )

        #expect(shelves.recordings.map(\.id) == ["now", "soon", "later"])
    }

    @Test func `finds other airings of the same show`() {
        let one = channel("1")
        let current = program("a", on: one, start: -10, title: "News")
        let programs = [
            current,
            program("b", on: one, start: 120, title: "News"),
            program("c", on: one, start: 60, title: "Film"),
            program("d", on: one, start: -200, minutes: 30, title: "News"),
        ]

        #expect(LiveTVShelves.otherAirings(of: current, in: programs, now: now).map(\.id) == ["b"])
    }
}
