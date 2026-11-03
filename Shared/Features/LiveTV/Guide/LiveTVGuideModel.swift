import SwiftUI

/// What the guide grid draws: one row per channel, its programs clipped to the loaded window.
struct LiveTVGuideGridModel: Equatable {
    let channels: [LiveTVChannel]
    let rows: [[LiveTVProgram]]
    let start: Date
    let end: Date
    var playingChannel: LiveTVChannelIdentity?
    var tintsCategories = true

    init(
        channels: [LiveTVChannel],
        programs: [LiveTVProgram],
        start: Date,
        end: Date,
        playingChannel: LiveTVChannelIdentity? = nil,
        tintsCategories: Bool = true,
    ) {
        let grouped = Dictionary(grouping: programs.filter { $0.endDate > start && $0.startDate < end }) {
            $0.channelIdentity
        }
        self.channels = channels
        rows = channels.map { channel in
            (grouped[channel.identity] ?? []).sorted { $0.startDate < $1.startDate }
        }
        self.start = start
        self.end = end
        self.playingChannel = playingChannel
        self.tintsCategories = tintsCategories
    }

    var geometry: LiveTVGuideGeometry {
        LiveTVGuideGeometry(start: start, end: end)
    }

    func program(at date: Date, row: Int) -> (index: Int, program: LiveTVProgram)? {
        guard rows.indices.contains(row) else { return nil }
        let programs = rows[row]
        if let index = programs.firstIndex(where: { $0.isAiring(at: date) }) {
            return (index, programs[index])
        }
        // A gap in the guide: the nearest program after the date, else the last one before it.
        if let index = programs.firstIndex(where: { $0.startDate > date }) {
            return (index, programs[index])
        }
        return programs.indices.last.map { ($0, programs[$0]) }
    }

    func row(of channel: LiveTVChannelIdentity) -> Int? {
        channels.firstIndex { $0.identity == channel }
    }
}

/// Horizontal positions in the guide, from times.
struct LiveTVGuideGeometry: Equatable {
    let start: Date
    let end: Date

    var contentWidth: CGFloat {
        LiveTVGuideMetrics.channelColumnWidth + LiveTVGuideMetrics.width(of: end.timeIntervalSince(start))
    }

    func x(for date: Date) -> CGFloat {
        LiveTVGuideMetrics.channelColumnWidth + LiveTVGuideMetrics.width(of: date.timeIntervalSince(start))
    }

    func date(atX x: CGFloat) -> Date {
        let minutes = (x - LiveTVGuideMetrics.channelColumnWidth) / LiveTVGuideMetrics.pointsPerMinute
        return start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    func frame(of program: LiveTVProgram) -> (x: CGFloat, width: CGFloat) {
        let visibleStart = max(program.startDate, start)
        let visibleEnd = min(program.endDate, end)
        let x = x(for: visibleStart)
        return (x, max(LiveTVGuideMetrics.width(of: visibleEnd.timeIntervalSince(visibleStart)), 4))
    }

    /// Half-hour marks of the time ruler.
    var slots: [Date] {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        components.minute = (components.minute ?? 0) >= 30 ? 30 : 0
        guard var slot = calendar.date(from: components) else { return [] }
        var result: [Date] = []
        while slot < end {
            if slot >= start {
                result.append(slot)
            }
            slot = slot.addingTimeInterval(1800)
        }
        return result
    }
}

/// Where the guide should scroll, and whether focus should land on the program there.
struct LiveTVGuideScrollRequest: Equatable {
    let id = UUID()
    let date: Date
    var channel: LiveTVChannelIdentity?
    var movesFocus = false
}
