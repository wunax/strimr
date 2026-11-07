import SwiftUI

enum LiveTVGuideFilter: Hashable {
    case all
    case favorites
    case category(LiveTVCategory)

    var title: LocalizedStringKey {
        switch self {
        case .all: "livetv.guide.filter.all"
        case .favorites: "livetv.shelf.favorites"
        case let .category(category): category.title
        }
    }
}

/// The program guide: an information banner, filters and the grid, or a channel list on iPhone.
struct LiveTVGuideView: View {
    @Bindable var store: LiveTVStore
    @Binding var scrollRequest: LiveTVGuideScrollRequest?
    let onOpenProgram: (LiveTVProgram) -> Void
    let onShowDetails: (LiveTVProgram) -> Void
    let onTuneChannel: (LiveTVChannel) -> Void
    /// Plays a program, from its beginning when the flag is set.
    let onTuneProgram: (LiveTVProgram, Bool) -> Void
    let onManageFavorites: () -> Void

    @Environment(MediaServices.self) private var services
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var filter = LiveTVGuideFilter.all
    @State private var focus = LiveTVGuideFocus()
    @State private var lastSeen: Date?

    /// After this long away, the guide comes back on the current time rather than where it was left.
    private static let recenterDelay: TimeInterval = 10 * 60

    private var usesChannelList: Bool {
        Self.usesChannelList(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    static func usesChannelList(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) -> Bool {
        #if os(iOS)
            horizontal == .compact && vertical != .compact
        #else
            false
        #endif
    }

    private var filters: [LiveTVGuideFilter] {
        let available = Set(store.programs.flatMap(\.categories))
        return [.all, .favorites] + LiveTVShelves.categoryOrder.filter(available.contains).map { .category($0) }
    }

    private var channels: [LiveTVChannel] {
        switch filter {
        case .all:
            return store.channels
        case .favorites:
            return store.favoriteChannels
        case let .category(category):
            let matching = Set(store.programs.filter { $0.categories.contains(category) }.map(\.channelIdentity))
            return store.channels.filter { matching.contains($0.identity) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if usesChannelList {
                filterBar
                LiveTVChannelListView(
                    store: store,
                    channels: channels,
                    onTuneChannel: onTuneChannel,
                    onTuneProgram: onTuneProgram,
                )
            } else {
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: 12) {
                        if showsBanner(in: proxy.size) {
                            LiveTVGuideFocusedBanner(store: store, channels: channels, focus: focus)
                        }
                        filterBar
                        grid
                    }
                }
            }
        }
        .onAppear {
            if let lastSeen, Date().timeIntervalSince(lastSeen) > Self.recenterDelay {
                jumpToNow(movesFocus: false)
            }
        }
        .onDisappear { lastSeen = Date() }
        .onChange(of: store.playbackEndedAt) { _, _ in
            guard let channel = store.lastPlayedChannel else { return }
            if !(store.guideStart ... store.guideEnd).contains(Date()) {
                Task { await store.jumpToNow() }
            }
            scrollRequest = LiveTVGuideScrollRequest(date: Date(), channel: channel, movesFocus: true)
        }
    }

    @ViewBuilder
    private var grid: some View {
        if channels.isEmpty {
            LiveTVEmptyState("livetv.empty.favorites", systemImage: "star", message: store.errorMessage)
        } else {
            LiveTVGuideGrid(
                model: LiveTVGuideGridModel(
                    channels: channels,
                    programs: store.programs,
                    start: store.guideStart,
                    end: store.guideEnd,
                    playingChannel: store.lastPlayedChannel,
                    tintsCategories: settingsManager.interface.tintsLiveTVGuideCategories,
                ),
                services: services,
                scrollRequest: scrollRequest,
                actions: LiveTVGuideGridActions(
                    openProgram: onOpenProgram,
                    showDetails: onShowDetails,
                    tuneChannel: onTuneChannel,
                    toggleFavorite: { channel in Task { await store.toggleFavorite(channel) } },
                    focusProgram: { [focus] in focus.program = $0 },
                    reachEdge: { forward in Task { await store.extendGuide(forward: forward) } },
                ),
            )
            .task(id: store.guideStart) {
                if scrollRequest == nil {
                    scrollRequest = LiveTVGuideScrollRequest(date: Date(), movesFocus: false)
                }
            }
        }
    }

    private func showsBanner(in size: CGSize) -> Bool {
        #if os(iOS)
            // iPad portrait keeps its height for the grid.
            size.width > size.height
        #else
            true
        #endif
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LayoutMetrics.chipSpacing) {
                ForEach(filters, id: \.self) { item in
                    Button { filter = item } label: { Text(item.title) }
                        .buttonStyle(.chip(isSelected: filter == item))
                }
                if filter == .favorites, store.channels.contains(where: \.isFavorite) {
                    Button(action: onManageFavorites) {
                        Label("livetv.favorites.manage", systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.chip(isSelected: false))
                }
                if filter != .favorites {
                    sortMenu
                }
                Divider().frame(height: 24)
                dayMenu
                Button { jumpToNow(movesFocus: true) } label: {
                    Label("livetv.guide.now", systemImage: "clock")
                }
                .buttonStyle(.chip(isSelected: false))
            }
            .padding(.horizontal, LayoutMetrics.pageMargin)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
        #if os(tvOS)
            .focusSection()
        #endif
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LiveTVChannelSort.allCases, id: \.self) { sort in
                Button { select(sort: sort) } label: {
                    if store.channelSort == sort {
                        Label(String(localized: sort.title), systemImage: "checkmark")
                    } else {
                        Text(sort.title)
                    }
                }
            }
        } label: {
            Label {
                Text(store.channelSort.title)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
        #if os(tvOS)
        .buttonStyle(.chip(isSelected: false))
        #else
        .menuStyle(.button)
        .buttonStyle(.chip(isSelected: false))
        #endif
    }

    private func select(sort: LiveTVChannelSort) {
        store.channelSort = sort
        settingsManager.setLiveTVChannelSort(sort, server: services.identity)
    }

    private var dayMenu: some View {
        Menu {
            ForEach(Self.days(), id: \.self) { day in
                Button { select(day: day) } label: {
                    Text(Self.dayTitle(day))
                }
            }
        } label: {
            Label {
                Text(Self.dayTitle(store.guideStart.addingTimeInterval(3600)))
            } icon: {
                Image(systemName: "calendar")
            }
        }
        #if os(tvOS)
        .buttonStyle(.chip(isSelected: false))
        #else
        .menuStyle(.button)
        .buttonStyle(.chip(isSelected: false))
        #endif
    }

    private func select(day: Date) {
        let start = LiveTVStore.guideStart(forDay: day)
        Task {
            await store.load(start: start, force: true)
            scrollRequest = LiveTVGuideScrollRequest(date: start, movesFocus: true)
        }
    }

    private func jumpToNow(movesFocus: Bool) {
        let now = Date()
        Task {
            if !(store.guideStart ... store.guideEnd).contains(now) {
                await store.jumpToNow()
            }
            scrollRequest = LiveTVGuideScrollRequest(date: now, movesFocus: movesFocus)
        }
    }

    static func days(from now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now)) }
    }

    static func dayTitle(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return String(localized: "livetv.guide.today")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(day, inSameDayAs: tomorrow)
        {
            return String(localized: "livetv.guide.tomorrow")
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

/// The focused or hovered program above the grid: what it is, when, and a picture.
/// The program under focus or the pointer. Kept out of the guide's state so that moving over the grid only
/// redraws the banner, not the whole grid.
@Observable
final class LiveTVGuideFocus {
    var program: LiveTVProgram?
}

private struct LiveTVGuideFocusedBanner: View {
    let store: LiveTVStore
    let channels: [LiveTVChannel]
    let focus: LiveTVGuideFocus

    private var program: LiveTVProgram? {
        if let focused = focus.program, channels.contains(where: { $0.identity == focused.channelIdentity }) {
            return store.programs.first { $0.identity == focused.identity } ?? focused
        }
        return channels.lazy.compactMap { store.currentProgram(on: $0.identity) }.first
    }

    var body: some View {
        if let program {
            LiveTVGuideBanner(program: program, channel: store.channel(for: program.channelIdentity))
                .padding(.horizontal, LayoutMetrics.pageMargin)
        }
    }
}

struct LiveTVGuideBanner: View {
    let program: LiveTVProgram
    let channel: LiveTVChannel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(program.title)
                    .font(.tileTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Text(facts)
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                badges
                if let summary = program.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.bodyText)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(bannerSummaryLines)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let path = program.thumbPath ?? program.artPath {
                ArtworkPathView(path: path, width: 480, height: 270)
                    .frame(width: bannerImageWidth, height: bannerImageWidth * 9 / 16)
                    .clipped()
                    .mediaArtworkStyle(.compact)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: bannerHeight, alignment: .top)
        .animation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion), value: program.identity)
    }

    private var facts: String {
        var parts = [
            program.startDate.formatted(date: .omitted, time: .shortened)
                + " – " + program.endDate.formatted(date: .omitted, time: .shortened),
        ]
        if let episode = program.episodeLabel {
            parts.append(episode)
        }
        if let channel {
            parts.append(channel.displayTitle)
        }
        return parts.joined(separator: " · ")
    }

    private var badges: some View {
        HStack(spacing: 6) {
            if program.isLive {
                badge("livetv.badge.live", color: .liveIndicator)
            }
            if program.isPremiere {
                badge("livetv.badge.new", color: .textPrimary)
            }
            if program.isScheduledForRecording {
                badge("livetv.badge.recorded", color: .recordingIndicator)
            }
        }
    }

    private func badge(_ title: LocalizedStringKey, color: Color) -> some View {
        Text(title)
            .font(.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.surfaceRaised, in: Capsule(style: .continuous))
    }

    private var bannerHeight: CGFloat {
        #if os(tvOS)
            200
        #else
            132
        #endif
    }

    private var bannerImageWidth: CGFloat {
        #if os(tvOS)
            340
        #else
            220
        #endif
    }

    private var bannerSummaryLines: Int {
        #if os(tvOS)
            3
        #else
            2
        #endif
    }
}
