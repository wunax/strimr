import Foundation

/// A channel in a What's On rail, with the program that gives the card its picture, if the guide has one.
struct LiveTVShelfItem: Identifiable, Hashable {
    let channel: LiveTVChannel
    let program: LiveTVProgram?

    var id: String {
        program.map { "\(channel.identity.storageKey)#\($0.id)" } ?? channel.identity.storageKey
    }
}

struct LiveTVShelf: Identifiable, Hashable {
    enum Kind: Hashable {
        case recent
        case favorites
        case onNow
        case upcoming
        case category(LiveTVCategory)
    }

    let kind: Kind
    let items: [LiveTVShelfItem]

    var id: Kind {
        kind
    }
}

/// The rails of the What's On screen, computed from what the store already loaded.
struct LiveTVShelves: Equatable {
    static let upcomingWindow: TimeInterval = 90 * 60
    static let minimumChannelsPerCategory = 3
    static let categoryOrder: [LiveTVCategory] = [.sports, .movie, .series, .news, .kids]

    let shelves: [LiveTVShelf]
    let recordings: [DVRRecording]

    init(
        channels: [LiveTVChannel],
        favorites favoriteChannels: [LiveTVChannel]? = nil,
        programs: [LiveTVProgram],
        onNowSections: [LiveTVOnNowSection] = [],
        recordings: [DVRRecording] = [],
        recentChannelKeys: [String] = [],
        now: Date,
    ) {
        let programsByChannel = Dictionary(grouping: programs, by: \.channelIdentity)
            .mapValues { $0.sorted { $0.startDate < $1.startDate } }
        let current = programsByChannel.compactMapValues { programs in
            programs.first { $0.isAiring(at: now) }
        }
        let sectionCategories = Self.sectionCategories(onNowSections)

        func item(_ channel: LiveTVChannel) -> LiveTVShelfItem {
            LiveTVShelfItem(channel: channel, program: current[channel.identity])
        }

        let channelsByKey = Dictionary(
            channels.map { ($0.identity.storageKey, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        let recent = recentChannelKeys.compactMap { channelsByKey[$0] }.map(item)
        let favorites = (favoriteChannels ?? channels.filter(\.isFavorite)).map(item)
        let onNow = channels.compactMap { channel in
            current[channel.identity].map { LiveTVShelfItem(channel: channel, program: $0) }
        }
        let upcoming = channels.compactMap { channel -> LiveTVShelfItem? in
            guard let next = programsByChannel[channel.identity]?.first(where: {
                $0.startDate > now && $0.startDate.timeIntervalSince(now) <= Self.upcomingWindow
            }) else { return nil }
            return LiveTVShelfItem(channel: channel, program: next)
        }
        .sorted { ($0.program?.startDate ?? now) < ($1.program?.startDate ?? now) }

        let categoryShelves = Self.categoryOrder.compactMap { category -> LiveTVShelf? in
            let items = onNow.filter { item in
                guard let program = item.program else { return false }
                let categories = program.categories.isEmpty
                    ? sectionCategories[program.id] ?? []
                    : program.categories
                return categories.contains(category)
            }
            guard Set(items.map(\.channel.identity)).count >= Self.minimumChannelsPerCategory else { return nil }
            return LiveTVShelf(kind: .category(category), items: items)
        }

        shelves = ([
            LiveTVShelf(kind: .recent, items: recent),
            LiveTVShelf(kind: .favorites, items: favorites),
            LiveTVShelf(kind: .onNow, items: onNow),
            LiveTVShelf(kind: .upcoming, items: upcoming),
        ] + categoryShelves)
            .map { LiveTVShelf(kind: $0.kind, items: Self.uniqueChannels($0.items)) }
            .filter { !$0.items.isEmpty }

        self.recordings = recordings
            .filter { $0.status == .recording || $0.status == .scheduled }
            .sorted { lhs, rhs in
                if (lhs.status == .recording) != (rhs.status == .recording) {
                    return lhs.status == .recording
                }
                return (lhs.startDate ?? .distantFuture) < (rhs.startDate ?? .distantFuture)
            }
    }

    /// The next airings of the same show in the loaded guide, the program itself left out.
    static func otherAirings(of program: LiveTVProgram, in programs: [LiveTVProgram], now: Date) -> [LiveTVProgram] {
        programs
            .filter { $0.identity != program.identity && $0.showTitle == program.showTitle && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func sectionCategories(_ sections: [LiveTVOnNowSection]) -> [String: Set<LiveTVCategory>] {
        var result: [String: Set<LiveTVCategory>] = [:]
        for section in sections {
            guard let category = LiveTVCategory(sectionID: section.id) else { continue }
            for program in section.programs {
                result[program.id, default: []].insert(category)
            }
        }
        return result
    }

    private static func uniqueChannels(_ items: [LiveTVShelfItem]) -> [LiveTVShelfItem] {
        var seen: Set<LiveTVChannelIdentity> = []
        return items.filter { seen.insert($0.channel.identity).inserted }
    }
}
