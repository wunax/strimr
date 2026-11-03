import SwiftUI

enum LiveTVProgramRecordingAction: Equatable {
    case cancelRecording(String)
    case deleteSeriesRule(String)
}

/// A program's page: what it is, when and where it airs, how to watch or record it, and its other airings.
struct LiveTVProgramDetailView: View {
    let program: LiveTVProgram
    @Bindable var store: LiveTVStore
    let onWatch: (LiveTVProgram) -> Void
    let onWatchFromStart: (LiveTVProgram) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var template: DVRRecordingTemplate?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var pendingAction: LiveTVProgramRecordingAction?
    @State private var isShowingRecordOptions = false

    private var current: LiveTVProgram {
        store.programs.first { $0.identity == program.identity } ?? program
    }

    private var channel: LiveTVChannel? {
        store.channel(for: program.channelIdentity)
    }

    private var canManageRecordings: Bool {
        store.dvr?.canManageRecordings == true
    }

    var body: some View {
        TaskModalNavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let summary = current.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.bodyText)
                            .foregroundStyle(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        #if os(tvOS)
                            .padding(16)
                            .modifier(TVModalReadingFocus())
                        #endif
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.facts)
                            .foregroundStyle(.red)
                    }
                    otherAirings
                }
                .padding(LayoutMetrics.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .taskModalTitle(verbatim: current.title)
            .taskModalActions(grouped: true) {
                if current.isCurrentlyAiring {
                    Button("livetv.watchLive", systemImage: "play.fill") { onWatch(current) }
                }
            } actions: {
                actionButtons
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: {
                        if !$0 {
                            pendingAction = nil
                        }
                    },
                ),
                titleVisibility: .visible,
            ) {
                switch pendingAction {
                case let .cancelRecording(id):
                    Button("livetv.recording.cancel", role: .destructive) { submit(.cancelRecording(id)) }
                case let .deleteSeriesRule(id):
                    Button("livetv.recording.stopSeries", role: .destructive) { submit(.deleteSeriesRule(id)) }
                case nil:
                    EmptyView()
                }
            } message: {
                Text(current.title)
            }
            .taskPresentation(isPresented: $isShowingRecordOptions, style: .compactModal) {
                if let template {
                    LiveTVRecordOptionsView(program: current, template: template, store: store)
                }
            }
            .task { await loadTemplate() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let path = current.artPath ?? current.thumbPath {
                ArtworkPathView(path: path, width: 1280, height: 720)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(maxWidth: 640)
                    .clipped()
                    .mediaArtworkStyle()
                    .accessibilityHidden(true)
            }
            if let episode = current.episodeLabel {
                Text(episode)
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
            }
            HStack(spacing: 12) {
                if let channel {
                    LiveTVChannelLogo(channel: channel)
                        .frame(width: 72, height: 40)
                    Text(channel.displayTitle)
                        .font(.facts)
                        .foregroundStyle(.textSecondary)
                }
            }
            Text(timeRange(current))
                .font(.facts)
                .foregroundStyle(.textSecondary)
            badges
            if current.isCurrentlyAiring {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    CardProgressBar(progress: current.progress(at: context.date))
                        .frame(maxWidth: 640)
                }
            }
        }
    }

    private var badges: some View {
        HStack(spacing: 8) {
            if current.isLive {
                badge("livetv.badge.live", color: .liveIndicator)
            }
            if current.isPremiere {
                badge("livetv.badge.new", color: .textPrimary)
            }
            if current.isRecording {
                badge("livetv.recording.status.recording", color: .recordingIndicator)
            } else if current.isScheduledForRecording {
                badge("livetv.badge.scheduled", color: .textPrimary)
            }
        }
    }

    private func badge(_ title: LocalizedStringKey, color: Color) -> some View {
        Text(title)
            .font(.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.surfaceRaised, in: Capsule(style: .continuous))
    }

    @ViewBuilder
    private var actionButtons: some View {
        if current.isCurrentlyAiring, store.service.supportsServerCaptureBuffer {
            Button("livetv.watchFromStart", systemImage: "backward.end.fill") { onWatchFromStart(current) }
        }
        if canManageRecordings {
            if let recordingID = current.recordingID {
                Button("livetv.stopRecord", systemImage: "stop.circle", role: .destructive) {
                    pendingAction = .cancelRecording(recordingID)
                }
                .disabled(isSubmitting)
            }
            if let ruleID = current.seriesRecordingID {
                Button("livetv.recording.stopSeries", systemImage: "stop.circle", role: .destructive) {
                    pendingAction = .deleteSeriesRule(ruleID)
                }
                .disabled(isSubmitting)
            }
            if !current.isScheduledForRecording, let template {
                if template.supportsSingle {
                    Button("livetv.record", systemImage: "record.circle") { record(current, series: false) }
                        .disabled(isSubmitting)
                }
                if template.supportsSeries {
                    Button("livetv.recordSeries", systemImage: "square.stack") { record(current, series: true) }
                        .disabled(isSubmitting)
                }
                Button("livetv.recording.options", systemImage: "slider.horizontal.3") {
                    isShowingRecordOptions = true
                }
            }
        }
        Button("common.done") { dismiss() }
    }

    @ViewBuilder
    private var otherAirings: some View {
        let airings = LiveTVShelves.otherAirings(of: current, in: store.programs, now: Date())
        if !airings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("livetv.program.otherAirings")
                    .font(.sectionTitle)
                    .foregroundStyle(.textPrimary)
                ForEach(airings) { airing in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(timeRange(airing))
                                .font(.rowTitle)
                            Text(store.channel(for: airing.channelIdentity)?.displayTitle ?? "")
                                .font(.cardMetadata)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if airing.isScheduledForRecording {
                            Image(systemName: "record.circle.fill")
                                .foregroundStyle(.recordingIndicator)
                                .accessibilityLabel(Text("livetv.badge.scheduled"))
                        } else if canManageRecordings {
                            Button("livetv.record", systemImage: "record.circle") { record(airing, series: false) }
                                .labelStyle(.iconOnly)
                                .disabled(isSubmitting)
                        }
                    }
                    .padding(12)
                    .background(.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    private var confirmationTitle: LocalizedStringKey {
        switch pendingAction {
        case .deleteSeriesRule: "livetv.recording.stopSeries.confirm"
        case .cancelRecording, nil: "livetv.recording.cancel.confirm"
        }
    }

    private func timeRange(_ program: LiveTVProgram) -> String {
        program.startDate.formatted(.dateTime.weekday().day().month().hour().minute())
            + " – " + program.endDate.formatted(date: .omitted, time: .shortened)
    }

    private func loadTemplate() async {
        guard !current.isScheduledForRecording, let dvr = store.dvr, dvr.canManageRecordings else { return }
        do {
            template = try await dvr.recordingTemplate(for: current)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            LiveTVErrorReporting.capture(error)
        }
    }

    private func record(_ program: LiveTVProgram, series: Bool) {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await store.record(program, series: series)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                if (error as? JellyfinAPIError) != .recordingConflict {
                    LiveTVErrorReporting.capture(error)
                }
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func submit(_ action: LiveTVProgramRecordingAction) {
        pendingAction = nil
        isSubmitting = true
        Task {
            do {
                switch action {
                case let .cancelRecording(id): try await store.cancelRecording(id: id)
                case let .deleteSeriesRule(id): try await store.deleteRule(id: id)
                }
                dismiss()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                LiveTVErrorReporting.capture(error)
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
