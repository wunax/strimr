import SwiftUI

/// Recordings as rails of cards (in progress, upcoming, completed), then the recording rules.
struct LiveTVRecordingsView: View {
    @Bindable var store: LiveTVStore
    let onPlayRecording: (MediaItem) -> Void
    let onOpenLibrary: (String) -> Void
    let onShowProgram: (LiveTVProgram) -> Void

    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var pendingRecordingCancellation: DVRRecording?
    @State private var pendingRecordingDeletion: DVRRecording?
    @State private var pendingRuleDeletion: DVRRecordingRule?
    @State private var selectedRule: DVRRecordingRule?

    private var canManage: Bool {
        store.dvr?.canManageRecordings == true
    }

    private var inProgress: [DVRRecording] {
        store.upcomingRecordings.filter { $0.status == .recording }
    }

    private var upcoming: [DVRRecording] {
        store.upcomingRecordings
            .filter { $0.status != .recording }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var cardSize: CGSize {
        LayoutMetrics.cardSize(
            for: .landscape,
            sizeClass: sizeClass,
            posterScale: settingsManager.interface.posterSize.scale,
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if store.dvr?.canManageRecordings == false {
                    Text("livetv.dvr.permissionDenied")
                        .font(.facts)
                        .foregroundStyle(.textSecondary)
                }
                if inProgress.isEmpty, upcoming.isEmpty, store.completedRecordings.isEmpty,
                   store.recordingRules.isEmpty
                {
                    LiveTVEmptyState("livetv.empty.recordings", systemImage: "record.circle")
                }
                rail("livetv.dvr.inProgress", recordings: inProgress)
                rail("livetv.dvr.scheduled", recordings: upcoming)
                rail("livetv.dvr.completed", recordings: store.completedRecordings)
                rules
            }
            .padding(.horizontal, LayoutMetrics.pageMargin)
            .padding(.bottom, 24)
        }
        .taskPresentation(item: $selectedRule) { rule in
            DVRRuleEditView(rule: rule, dvr: store.dvr) { await store.refreshDVR() }
        }
        .confirmationDialog(
            "livetv.recording.cancel.confirm",
            isPresented: isPresented($pendingRecordingCancellation),
            titleVisibility: .visible,
        ) {
            Button("livetv.recording.cancel", role: .destructive) {
                guard let recording = pendingRecordingCancellation else { return }
                perform { try await store.cancelRecording(id: recording.id) }
            }
        } message: {
            if let recording = pendingRecordingCancellation {
                Text(recording.title)
            }
        }
        .confirmationDialog(
            "livetv.recording.delete.confirm",
            isPresented: isPresented($pendingRecordingDeletion),
            titleVisibility: .visible,
        ) {
            Button("common.delete", role: .destructive) {
                guard let recording = pendingRecordingDeletion, let dvr = store.dvr else { return }
                perform {
                    try await dvr.deleteCompleted(recordingID: recording.id)
                    await store.refreshDVR()
                }
            }
        } message: {
            if let recording = pendingRecordingDeletion {
                Text(recording.title)
            }
        }
        .confirmationDialog(
            "livetv.recording.stopSeries.confirm",
            isPresented: isPresented($pendingRuleDeletion),
            titleVisibility: .visible,
        ) {
            Button("common.delete", role: .destructive) {
                guard let rule = pendingRuleDeletion else { return }
                perform { try await store.deleteRule(id: rule.id) }
            }
        } message: {
            if let rule = pendingRuleDeletion {
                Text(rule.title)
            }
        }
    }

    @ViewBuilder
    private func rail(_ title: LocalizedStringKey, recordings: [DVRRecording]) -> some View {
        if !recordings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.sectionTitle)
                    .foregroundStyle(.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: LayoutMetrics.railSpacing(for: .landscape)) {
                        ForEach(recordings) { recording in
                            LiveTVRecordingCard(
                                recording: recording,
                                program: program(for: recording),
                                size: cardSize,
                                onOpen: { open(recording) },
                                onCancel: canManage && recording.status != .completed
                                    ? { pendingRecordingCancellation = recording }
                                    : nil,
                                onDelete: recording.status == .completed && store.dvr?.canDeleteRecordings == true
                                    ? { pendingRecordingDeletion = recording }
                                    : nil,
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
    }

    @ViewBuilder
    private var rules: some View {
        if !store.recordingRules.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("livetv.dvr.rules")
                    .font(.sectionTitle)
                    .foregroundStyle(.textPrimary)
                ForEach(store.recordingRules) { rule in
                    ruleRow(rule)
                }
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    private func ruleRow(_ rule: DVRRecordingRule) -> some View {
        HStack(spacing: 12) {
            Button { selectedRule = rule } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.title)
                        .font(.rowTitle)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(rule.modeTitle)
                        if let library = rule.targetLibraryTitle {
                            Text(verbatim: "·")
                            Text(library)
                        }
                    }
                    .font(.cardMetadata)
                    // Hierarchical: the row is a button, which turns white when focused on tvOS.
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .contentShape(Rectangle())
            }
            #if os(tvOS)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: LayoutMetrics.cardCornerRadius))
            #else
            .buttonStyle(.plain)
            .background(.surfaceSubtle, in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius))
            #endif
            .contextMenu {
                if canManage {
                    Button("common.delete", systemImage: "trash", role: .destructive) { pendingRuleDeletion = rule }
                }
            }
            if let libraryID = rule.targetLibraryID {
                Button("livetv.dvr.openLibrary", systemImage: "rectangle.stack") { onOpenLibrary(libraryID) }
                    .actionButtonStyle(.secondary)
            }
        }
    }

    private func program(for recording: DVRRecording) -> LiveTVProgram? {
        recording.programID.flatMap { id in store.programs.first { $0.id == id } }
    }

    private func open(_ recording: DVRRecording) {
        if let media = recording.playableMedia {
            onPlayRecording(media)
        } else if let program = program(for: recording) {
            onShowProgram(program)
        } else if canManage, recording.status != .completed {
            pendingRecordingCancellation = recording
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                LiveTVErrorReporting.capture(error)
            }
        }
    }

    private func isPresented(_ item: Binding<(some Any)?>) -> Binding<Bool> {
        Binding(
            get: { item.wrappedValue != nil },
            set: {
                if !$0 {
                    item.wrappedValue = nil
                }
            },
        )
    }
}
