import CoreGraphics
import Foundation
@testable import Strimr
import Testing

@MainActor
struct LiveTVGuideModelTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private let channel = LiveTVChannel(
        providerID: "1",
        title: "One",
        callSign: nil,
        number: "1",
        thumbPath: nil,
        artPath: nil,
        lineupID: nil,
        dvrID: nil,
        isHD: true,
        isFavorite: false,
    )

    private func program(_ id: String, from minutes: TimeInterval, to end: TimeInterval) -> LiveTVProgram {
        LiveTVProgram(
            id: id,
            channelID: "1",
            channelIdentity: channel.identity,
            title: id,
            seriesTitle: nil,
            summary: nil,
            startDate: start.addingTimeInterval(minutes * 60),
            endDate: start.addingTimeInterval(end * 60),
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
        )
    }

    @Test func `keeps only the programs of the window in each row`() {
        let model = LiveTVGuideGridModel(
            channels: [channel],
            programs: [
                program("before", from: -60, to: -10),
                program("a", from: -10, to: 30),
                program("b", from: 30, to: 90),
            ],
            start: start,
            end: start.addingTimeInterval(3600),
        )

        #expect(model.rows == [[program("a", from: -10, to: 30), program("b", from: 30, to: 90)]])
    }

    @Test func `finds the program at a time, or the next one across a gap`() {
        let model = LiveTVGuideGridModel(
            channels: [channel],
            programs: [program("a", from: 0, to: 30), program("b", from: 60, to: 90)],
            start: start,
            end: start.addingTimeInterval(7200),
        )

        #expect(model.program(at: start.addingTimeInterval(10 * 60), row: 0)?.program.id == "a")
        #expect(model.program(at: start.addingTimeInterval(45 * 60), row: 0)?.program.id == "b")
        #expect(model.program(at: start.addingTimeInterval(100 * 60), row: 0)?.program.id == "b")
        #expect(model.program(at: start, row: 3) == nil)
    }

    @Test func `places programs by time and clips them to the window`() {
        let geometry = LiveTVGuideGeometry(start: start, end: start.addingTimeInterval(3600))
        let frame = geometry.frame(of: program("a", from: -30, to: 30))

        #expect(frame.x == LiveTVGuideMetrics.channelColumnWidth)
        #expect(frame.width == LiveTVGuideMetrics.width(of: 1800))
        #expect(geometry.date(atX: geometry.x(for: start.addingTimeInterval(900))) == start.addingTimeInterval(900))
    }

    @Test func `pins a program running past the channel column to its edge`() {
        let column = LiveTVGuideMetrics.channelColumnWidth
        let running = CGRect(x: column + 2, y: 0, width: 300, height: 10)
        let pinned = LiveTVGuideGeometry.visibleCellFrame(running, scrollX: 100)

        #expect(pinned.minX == 100 + column + 2)
        #expect(pinned.maxX == running.maxX)
        #expect(LiveTVGuideGeometry.visibleCellFrame(running, scrollX: 0) == running)

        let hidden = CGRect(x: column + 2, y: 0, width: 50, height: 10)
        #expect(LiveTVGuideGeometry.visibleCellFrame(hidden, scrollX: 100) == hidden)
    }

    @Test func `marks the ruler every half hour`() throws {
        let aligned = try #require(Calendar.current.date(bySetting: .minute, value: 0, of: start))
        let geometry = LiveTVGuideGeometry(
            start: aligned.addingTimeInterval(600),
            end: aligned.addingTimeInterval(7200),
        )

        #expect(geometry.slots == [
            aligned.addingTimeInterval(1800),
            aligned.addingTimeInterval(3600),
            aligned.addingTimeInterval(5400),
        ])
    }

    @Test func `merging a loaded block keeps programs once`() {
        let a = program("a", from: 0, to: 30)
        let b = program("b", from: 30, to: 60)

        #expect(LiveTVStore.merging([b, a], [a, program("c", from: 60, to: 90)]).map(\.id) == ["a", "b", "c"])
    }

    @Test func `a later day starts in the morning`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))

        #expect(LiveTVStore.guideStart(forDay: now, now: now, calendar: calendar) == now)
        #expect(calendar
            .component(.hour, from: LiveTVStore.guideStart(forDay: tomorrow, now: now, calendar: calendar)) == 6)
    }

    #if os(macOS)
        @Test func `the visible window stays put within half a viewport`() {
            let first = LiveTVGuideVisibleWindow(visibleRect: CGRect(x: 1000, y: 0, width: 800, height: 600))
            let near = LiveTVGuideVisibleWindow(visibleRect: CGRect(x: 1199, y: 500, width: 800, height: 600))
            let far = LiveTVGuideVisibleWindow(visibleRect: CGRect(x: 1200, y: 0, width: 800, height: 600))

            #expect(first == near)
            #expect(first != far)
        }

        @Test func `the visible window covers the viewport and half of it on each side`() {
            for x in stride(from: -100.0, through: 3000, by: 37) {
                let window = LiveTVGuideVisibleWindow(visibleRect: CGRect(x: x, y: 0, width: 800, height: 600))

                #expect(window.contains(x: x - 400, width: 1))
                #expect(window.contains(x: x + 1200, width: 1))
                #expect(!window.contains(x: x - 2000, width: 1))
                #expect(!window.contains(x: x + 3000, width: 1))
            }
        }
    #endif
}
