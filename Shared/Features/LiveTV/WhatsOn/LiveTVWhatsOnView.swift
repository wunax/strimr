import SwiftUI

/// Entry screen of Live TV: what is on air now and soon, in rails, under the program in focus.
struct LiveTVWhatsOnView: View {
    @Bindable var store: LiveTVStore
    let actions: LiveTVCardActions
    let onOpenRecording: (DVRRecording) -> Void

    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var focusedItem: LiveTVShelfItem?
    @State private var focusTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let shelves = store.shelves(now: context.date)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if let hero = heroItem(in: shelves) {
                        LiveTVHeroView(
                            item: hero,
                            onWatch: { actions.watch(hero.channel, hero.program) },
                            onDetails: { hero.program.map { actions.details?($0) } },
                        )
                    }
                    if shelves.shelves.isEmpty, shelves.recordings.isEmpty {
                        LiveTVEmptyState("livetv.empty.onNow", systemImage: "clock", message: store.errorMessage)
                    }
                    ForEach(shelves.shelves) { shelf in
                        rail(shelf)
                    }
                    if !shelves.recordings.isEmpty {
                        recordingsRail(shelves.recordings)
                    }
                }
                .padding(.horizontal, LayoutMetrics.pageMargin)
                .padding(.bottom, 24)
            }
        }
    }

    private var cardSize: CGSize {
        LayoutMetrics.cardSize(
            for: .landscape,
            sizeClass: sizeClass,
            posterScale: settingsManager.interface.posterSize.scale,
        )
    }

    private func heroItem(in shelves: LiveTVShelves) -> LiveTVShelfItem? {
        #if os(tvOS)
            if let focusedItem {
                return focusedItem
            }
        #endif
        return shelves.shelves.first { $0.kind == .onNow }?.items.first
            ?? shelves.shelves.first?.items.first
    }

    private func rail(_ shelf: LiveTVShelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.kind.title)
                .font(.sectionTitle)
                .foregroundStyle(.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: LayoutMetrics.railSpacing(for: .landscape)) {
                    ForEach(shelf.items) { item in
                        LiveTVProgramCard(
                            item: item,
                            size: cardSize,
                            showsStartTime: shelf.kind == .upcoming,
                            onOpen: { open(item) },
                            onFocus: { focus(item) },
                            contextActions: actions,
                        )
                    }
                }
                .padding(.vertical, LayoutMetrics.railVerticalInset)
            }
            .scrollClipDisabled()
            .railBleed(pageMargin: LayoutMetrics.pageMargin)
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func recordingsRail(_ recordings: [DVRRecording]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("livetv.dvr.upcoming")
                .font(.sectionTitle)
                .foregroundStyle(.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: LayoutMetrics.railSpacing(for: .landscape)) {
                    ForEach(recordings) { recording in
                        LiveTVRecordingCard(
                            recording: recording,
                            program: recording.programID.flatMap { id in store.programs.first { $0.id == id } },
                            size: cardSize,
                            onOpen: { onOpenRecording(recording) },
                        )
                    }
                }
                .padding(.vertical, LayoutMetrics.railVerticalInset)
            }
            .scrollClipDisabled()
            .railBleed(pageMargin: LayoutMetrics.pageMargin)
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func open(_ item: LiveTVShelfItem) {
        guard let program = item.program, !program.isCurrentlyAiring else {
            actions.watch(item.channel, item.program)
            return
        }
        actions.details?(program)
    }

    private func focus(_ item: LiveTVShelfItem) {
        focusTask?.cancel()
        focusTask = Task {
            try? await Task.sleep(for: Motion.heroFocusDelay)
            guard !Task.isCancelled else { return }
            focusedItem = item
        }
    }
}

extension LiveTVShelf.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .recent: "livetv.shelf.recent"
        case .favorites: "livetv.shelf.favorites"
        case .onNow: "livetv.shelf.onNow"
        case .upcoming: "livetv.shelf.upcoming"
        case let .category(category): category.title
        }
    }
}

extension LiveTVCategory {
    var title: LocalizedStringKey {
        switch self {
        case .sports: "livetv.category.sports"
        case .movie: "livetv.category.movies"
        case .series: "livetv.category.series"
        case .news: "livetv.category.news"
        case .kids: "livetv.category.kids"
        }
    }
}
