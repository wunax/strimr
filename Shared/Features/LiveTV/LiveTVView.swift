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

    @Bindable var store: LiveTVStore
    let onPlayLive: (LiveTVLaunchContext) -> Void
    let onPlayRecording: (MediaItem) -> Void
    let onOpenLibrary: (String) -> Void

    @Environment(MediaServices.self) private var services
    @Environment(SettingsManager.self) private var settingsManager
    @State private var section = LiveTVSection.onNow
    @State private var favoritesOnly = false
    @State private var selectedProgram: LiveTVProgram?
    @State private var isManagingFavorites = false

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
                        favoritesOnly: favoritesOnly,
                        onTuneChannel: tune,
                        onSelectProgram: { selectedProgram = $0 },
                    )
                case .recordings:
                    LiveTVRecordingsView(
                        store: store,
                        onPlayRecording: onPlayRecording,
                        onOpenLibrary: onOpenLibrary,
                    )
                }
            }
        }
        .navigationTitle("livetv.title")
        .toolbar {
            ToolbarItemGroup {
                if section == .guide {
                    Toggle("livetv.favoritesOnly", systemImage: "star.fill", isOn: $favoritesOnly)
                    Button("livetv.favorites.manage", systemImage: "arrow.up.arrow.down") {
                        isManagingFavorites = true
                    }
                }
                Button("common.refresh", systemImage: "arrow.clockwise") {
                    Task { await store.load(start: store.guideStart, force: true) }
                }
            }
        }
        .task { await store.load() }
        .onAppear {
            if let saved = settingsManager.liveTVSection(server: services.identity)
                .flatMap(LiveTVSection.init(rawValue:)), sections.contains(saved)
            {
                section = saved
            }
        }
        .onChange(of: section) { _, newValue in
            settingsManager.setLiveTVSection(newValue.rawValue, server: services.identity)
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
    }

    private var sectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LayoutMetrics.chipSpacing) {
                ForEach(sections) { item in
                    Button { section = item } label: {
                        Text(item.title)
                    }
                    .buttonStyle(.chip(isSelected: section == item))
                }
            }
            .padding(.horizontal, LayoutMetrics.pageMargin)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
        #if os(tvOS)
            .focusSection()
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
