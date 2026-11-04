import SwiftUI

struct LiveTVView: View {
    enum LiveTVSection: String, CaseIterable, Identifiable {
        case onNow
        case guide
        case recordings

        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            switch self {
            case .onNow: "livetv.section.onNow"
            case .guide: "livetv.section.guide"
            case .recordings: "livetv.section.dvr"
            }
        }
    }

    /// A search result waiting for the search to close, since a sheet cannot open while another one is closing.
    private enum SearchSelection {
        case channel(LiveTVChannel)
        case program(LiveTVProgram)
    }

    @Bindable var store: LiveTVStore
    let onPlayLive: (LiveTVLaunchContext) -> Void
    let onPlayRecording: (MediaItem) -> Void
    let onOpenLibrary: (String) -> Void

    @Environment(MediaServices.self) private var services
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var section = LiveTVSection.onNow
    @State private var selectedProgram: LiveTVProgram?
    @State private var isManagingFavorites = false
    @State private var isSearching = false
    @State private var guideScrollRequest: LiveTVGuideScrollRequest?
    @State private var scheduleChannel: LiveTVChannel?
    @State private var pendingSearchSelection: SearchSelection?

    private var sections: [LiveTVSection] {
        store.dvr == nil ? [.onNow, .guide] : LiveTVSection.allCases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionChips

            if store.isLoading, store.channels.isEmpty {
                Spacer()
                ProgressView()
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if !store.isAvailable {
                LiveTVEmptyState("livetv.unavailable", systemImage: "tv.slash", message: store.errorMessage)
            } else if store.channels.isEmpty {
                LiveTVEmptyState("livetv.empty.channels", systemImage: "tv", message: store.errorMessage)
            } else {
                switch section {
                case .onNow:
                    LiveTVWhatsOnView(store: store, actions: cardActions, onOpenRecording: openRecording)
                case .guide:
                    LiveTVGuideView(
                        store: store,
                        scrollRequest: $guideScrollRequest,
                        onOpenProgram: open,
                        onShowDetails: { selectedProgram = $0 },
                        onTuneChannel: tune,
                        onTuneProgram: { tune($0, fromStart: $1) },
                        onManageFavorites: { isManagingFavorites = true },
                    )
                case .recordings:
                    LiveTVRecordingsView(
                        store: store,
                        onPlayRecording: onPlayRecording,
                        onOpenLibrary: onOpenLibrary,
                        onShowProgram: { selectedProgram = $0 },
                    )
                }
            }
        }
        #if !os(tvOS)
        .navigationTitle("livetv.title")
        .toolbar {
            ToolbarItemGroup {
                searchButton
                refreshButton
            }
        }
        #endif
        .task { await store.load() }
        .onAppear {
            #if DEBUG
                if DemoMode.isEnabled, let demo = DemoLiveTV.section.flatMap(LiveTVSection.init(rawValue:)) {
                    section = demo
                    return
                }
            #endif
            if let saved = settingsManager.liveTVSection(server: services.identity)
                .flatMap(LiveTVSection.init(rawValue:)), sections.contains(saved)
            {
                section = saved
            }
        }
        .onChange(of: section) { _, newValue in
            settingsManager.setLiveTVSection(newValue.rawValue, server: services.identity)
            // Leaving the section destroys the grid, and a new grid would replay the request.
            if newValue != .guide {
                guideScrollRequest = nil
            }
        }
        .taskPresentation(item: $selectedProgram) { program in
            LiveTVProgramDetailView(
                program: program,
                store: store,
                onWatch: { tune($0) },
                onWatchFromStart: { tune($0, fromStart: true) },
            )
        }
        .taskPresentation(isPresented: $isManagingFavorites) {
            FavoriteChannelOrderView(store: store)
        }
        .taskPresentation(item: $scheduleChannel) { channel in
            LiveTVChannelScheduleView(
                store: store,
                channel: channel,
                onTuneChannel: tune,
                onTuneProgram: { tune($0, fromStart: $1) },
            )
        }
        .taskPresentation(isPresented: $isSearching, onDismiss: openPendingSearchSelection) {
            LiveTVGuideSearchView(
                store: store,
                onSelectChannel: showInGuide,
                onSelectProgram: showInGuide,
            )
        }
    }

    private var searchButton: some View {
        Button { isSearching = true } label: {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel(Text("livetv.search.title"))
        .disabled(store.channels.isEmpty)
    }

    private var refreshButton: some View {
        Button {
            Task { await store.load(start: store.guideStart, force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel(Text("common.refresh"))
    }

    private var sectionChipButtons: some View {
        ForEach(sections) { item in
            Button { section = item } label: {
                Text(item.title)
            }
            .buttonStyle(.chip(isSelected: section == item))
        }
    }

    private var sectionChips: some View {
        #if os(tvOS)
            // No navigation bar on tvOS: its actions sit at the end of the chip row to save vertical space.
            HStack(spacing: LayoutMetrics.chipSpacing) {
                sectionChipButtons
                Spacer()
                Group {
                    searchButton
                    refreshButton
                }
                .buttonStyle(.chip(isSelected: false))
            }
            .padding(.horizontal, LayoutMetrics.pageMargin)
            .padding(.vertical, 8)
            .focusSection()
        #else
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutMetrics.chipSpacing) {
                    sectionChipButtons
                }
                .padding(.horizontal, LayoutMetrics.pageMargin)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        #endif
    }

    private var cardActions: LiveTVCardActions {
        LiveTVCardActions(
            watch: { channel, program in
                if let program, program.isCurrentlyAiring {
                    tune(program)
                } else {
                    tune(channel)
                }
            },
            details: { selectedProgram = $0 },
            record: store.dvr?.canManageRecordings == true ? { program in
                Task {
                    do {
                        try await store.record(program, series: false)
                    } catch {
                        guard !Task.isCancelled, !error.isCancellation else { return }
                        if (error as? JellyfinAPIError) != .recordingConflict {
                            LiveTVErrorReporting.capture(error)
                        }
                    }
                }
            } : nil,
            toggleFavorite: { channel in Task { await store.toggleFavorite(channel) } },
        )
    }

    /// On air plays, later opens the program page.
    private func open(_ program: LiveTVProgram) {
        if program.isCurrentlyAiring {
            tune(program)
        } else {
            selectedProgram = program
        }
    }

    /// The channel list has no position to scroll to, so a search result opens its own page there.
    private var usesChannelList: Bool {
        LiveTVGuideView.usesChannelList(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    private func openPendingSearchSelection() {
        switch pendingSearchSelection {
        case let .channel(channel): scheduleChannel = channel
        case let .program(program): selectedProgram = program
        case nil: break
        }
        pendingSearchSelection = nil
    }

    private func showInGuide(_ channel: LiveTVChannel) {
        section = .guide
        if usesChannelList {
            pendingSearchSelection = .channel(channel)
        } else {
            guideScrollRequest = LiveTVGuideScrollRequest(date: Date(), channel: channel.identity, movesFocus: true)
        }
    }

    /// A search result can air past what the guide has loaded.
    private func showInGuide(_ program: LiveTVProgram) {
        section = .guide
        if usesChannelList {
            pendingSearchSelection = .program(program)
            return
        }
        let date = max(program.startDate, Date())
        let request = LiveTVGuideScrollRequest(date: date, channel: program.channelIdentity, movesFocus: true)
        if store.guideCovers(date) {
            guideScrollRequest = request
        } else {
            Task {
                await store.load(start: date, force: true)
                if store.guideCovers(date) {
                    guideScrollRequest = request
                }
            }
        }
    }

    private func openRecording(_ recording: DVRRecording) {
        if let media = recording.playableMedia {
            onPlayRecording(media)
        } else if let program = recording.programID.flatMap({ id in store.programs.first { $0.id == id } }) {
            selectedProgram = program
        }
    }

    private func tune(_ program: LiveTVProgram, fromStart: Bool = false) {
        guard let index = store.channels.firstIndex(where: { $0.identity == program.channelIdentity }) else { return }
        selectedProgram = nil
        onPlayLive(
            LiveTVLaunchContext(
                channels: store.channels,
                selectedIndex: index,
                program: program,
                startsFromBeginning: fromStart,
            ),
        )
    }

    private func tune(_ channel: LiveTVChannel) {
        guard let index = store.channels.firstIndex(where: { $0.identity == channel.identity }) else { return }
        onPlayLive(LiveTVLaunchContext(channels: store.channels, selectedIndex: index))
    }
}
