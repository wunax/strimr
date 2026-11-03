import SwiftUI

struct LiveTVView: View {
    enum LiveTVSection: String, CaseIterable, Identifiable {
        case guide
        case onNow
        case dvr

        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            switch self {
            case .guide: "livetv.section.guide"
            case .onNow: "livetv.section.onNow"
            case .dvr: "livetv.section.dvr"
            }
        }
    }

    @Bindable var store: LiveTVStore
    let onPlayLive: (LiveTVLaunchContext) -> Void
    let onPlayRecording: (MediaItem) -> Void
    let onOpenLibrary: (String) -> Void

    @State private var section = LiveTVSection.guide
    @State private var favoritesOnly = false
    @State private var selectedProgram: LiveTVProgram?
    @State private var isManagingFavorites = false

    var body: some View {
        VStack(spacing: 12) {
            Picker("livetv.title", selection: $section) {
                ForEach(LiveTVSection.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if store.isLoading, store.channels.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if !store.isAvailable {
                LiveTVEmptyState("livetv.unavailable", systemImage: "tv.slash", message: store.errorMessage)
            } else if store.channels.isEmpty {
                LiveTVEmptyState("livetv.empty.channels", systemImage: "tv", message: store.errorMessage)
            } else {
                switch section {
                case .guide:
                    LiveTVGuideView(
                        store: store,
                        favoritesOnly: favoritesOnly,
                        onTuneChannel: tune,
                        onSelectProgram: { selectedProgram = $0 },
                    )
                case .onNow:
                    LiveTVWhatsOnView(store: store, onOpenProgram: openOnNowProgram)
                case .dvr:
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
        .taskPresentation(item: $selectedProgram) { program in
            LiveTVProgramDetailView(
                program: program,
                channel: store.channels.first { $0.identity == program.channelIdentity },
                dvr: store.dvr,
                supportsWatchFromStart: store.service.supportsServerCaptureBuffer,
                onWatch: { tune(program) },
                onWatchFromStart: { tune(program, fromStart: true) },
                onChanged: { await store.refreshDVR() },
            )
        }
        .taskPresentation(isPresented: $isManagingFavorites) {
            FavoriteChannelOrderView(store: store)
        }
    }

    private func openOnNowProgram(_ program: LiveTVProgram) {
        if program.isCurrentlyAiring {
            tune(program)
        } else {
            selectedProgram = program
        }
    }

    private func tune(_ program: LiveTVProgram, fromStart: Bool = false) {
        guard let index = store.channels.firstIndex(where: { $0.identity == program.channelIdentity }) else { return }
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
