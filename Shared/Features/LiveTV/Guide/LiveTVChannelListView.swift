import SwiftUI

/// The guide on iPhone: one row per channel with what is on now and next.
struct LiveTVChannelListView: View {
    @Bindable var store: LiveTVStore
    let channels: [LiveTVChannel]
    let onTuneChannel: (LiveTVChannel) -> Void

    @State private var scheduleChannel: LiveTVChannel?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            List(channels) { channel in
                Button { onTuneChannel(channel) } label: {
                    row(channel, now: context.date)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("livetv.watchLive", systemImage: "play.fill") { onTuneChannel(channel) }
                    Button("livetv.guide.channelSchedule", systemImage: "list.bullet") { scheduleChannel = channel }
                    Button(
                        channel.isFavorite ? "livetv.favorite.remove" : "livetv.favorite.add",
                        systemImage: channel.isFavorite ? "star.slash" : "star",
                    ) {
                        Task { await store.toggleFavorite(channel) }
                    }
                }
                #if os(iOS)
                .swipeActions {
                    Button("livetv.guide.channelSchedule", systemImage: "list.bullet") { scheduleChannel = channel }
                        .tint(.surfaceRaised)
                }
                #endif
            }
            .listStyle(.plain)
        }
        .taskPresentation(item: $scheduleChannel) { channel in
            LiveTVChannelScheduleView(store: store, channel: channel, onTuneChannel: onTuneChannel)
        }
    }

    private func row(_ channel: LiveTVChannel, now: Date) -> some View {
        HStack(spacing: 12) {
            LiveTVChannelLogo(channel: channel)
                .frame(width: 64, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                if let current = store.currentProgram(on: channel.identity, at: now) {
                    Text(current.title)
                        .font(.rowTitle)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                    CardProgressBar(progress: current.progress(at: now))
                        .frame(maxWidth: 160)
                } else {
                    Text(channel.displayTitle)
                        .font(.rowTitle)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                }
                if let next = store.nextProgram(on: channel.identity, after: now) {
                    Text(
                        "livetv.guide.next \(next.startDate.formatted(date: .omitted, time: .shortened)) \(next.title)",
                    )
                    .font(.cardMetadata)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button("livetv.guide.channelSchedule", systemImage: "list.bullet") { scheduleChannel = channel }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.textSecondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// One channel's programs in order, on iPhone, with the day picker of the guide.
struct LiveTVChannelScheduleView: View {
    @Bindable var store: LiveTVStore
    let channel: LiveTVChannel
    let onTuneChannel: (LiveTVChannel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProgram: LiveTVProgram?

    private var programs: [LiveTVProgram] {
        store.programs
            .filter { $0.channelIdentity == channel.identity && $0.endDate > store.guideStart }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        TaskModalNavigationView {
            List {
                ForEach(programs) { program in
                    Button { selectedProgram = program } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(program.startDate, format: .dateTime.hour().minute())
                                .font(.facts.monospacedDigit())
                                .foregroundStyle(program.isCurrentlyAiring ? Color.liveIndicator : .secondary)
                                .frame(width: 56, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(program.title)
                                    .font(.rowTitle)
                                if let episode = program.episodeLabel {
                                    Text(episode)
                                        .font(.cardMetadata)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            if program.isScheduledForRecording {
                                Image(systemName: "record.circle.fill")
                                    .foregroundStyle(.recordingIndicator)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button("livetv.guide.loadMore") {
                    Task { await store.extendGuide(forward: true) }
                }
            }
            .listStyle(.plain)
            .taskModalTitle(verbatim: channel.displayTitle)
            .taskModalActions {
                Button("livetv.watchLive") {
                    dismiss()
                    onTuneChannel(channel)
                }
            } actions: {
                Menu {
                    ForEach(LiveTVGuideView.days(), id: \.self) { day in
                        Button(LiveTVGuideView.dayTitle(day)) {
                            Task { await store.load(start: LiveTVStore.guideStart(forDay: day), force: true) }
                        }
                    }
                } label: {
                    Label("livetv.guide.day", systemImage: "calendar")
                }
            }
            .taskPresentation(item: $selectedProgram) { program in
                LiveTVProgramDetailView(
                    program: program,
                    store: store,
                    onWatch: { _ in
                        selectedProgram = nil
                        dismiss()
                        onTuneChannel(channel)
                    },
                    onWatchFromStart: { _ in },
                )
            }
        }
    }
}
