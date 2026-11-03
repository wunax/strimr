import SwiftUI

struct LiveTVRecordingsView: View {
    @Bindable var store: LiveTVStore
    let onPlayRecording: (MediaItem) -> Void
    let onOpenLibrary: (String) -> Void

    @State private var pendingRecordingCancellation: DVRRecording?
    @State private var pendingRecordingDeletion: DVRRecording?
    @State private var selectedRule: DVRRecordingRule?

    var body: some View {
        dvr
            .taskPresentation(item: $selectedRule) { rule in
                DVRRuleEditView(rule: rule, dvr: store.dvr) { await store.refreshDVR() }
            }
            .confirmationDialog(
                "livetv.recording.cancel.confirm",
                isPresented: Binding(
                    get: { pendingRecordingCancellation != nil },
                    set: {
                        if !$0 {
                            pendingRecordingCancellation = nil
                        }
                    },
                ),
                titleVisibility: .visible,
            ) {
                Button("livetv.recording.cancel", role: .destructive) {
                    cancelPendingRecording()
                }
            } message: {
                if let recording = pendingRecordingCancellation {
                    Text(recording.title)
                }
            }
            .confirmationDialog(
                "livetv.recording.delete.confirm",
                isPresented: Binding(
                    get: { pendingRecordingDeletion != nil },
                    set: {
                        if !$0 {
                            pendingRecordingDeletion = nil
                        }
                    },
                ),
                titleVisibility: .visible,
            ) {
                Button("common.delete", role: .destructive) {
                    guard let recording = pendingRecordingDeletion, let dvr = store.dvr else { return }
                    Task {
                        do {
                            try await dvr.deleteCompleted(recordingID: recording.id)
                            await store.refreshDVR()
                        } catch {
                            guard !Task.isCancelled, !error.isCancellation else { return }
                            LiveTVErrorReporting.capture(error)
                        }
                    }
                }
            }
    }

    private var dvr: some View {
        List {
            if store.dvr == nil {
                Text("livetv.dvr.unsupported")
            } else if store.dvr?.canManageRecordings == false {
                Text("livetv.dvr.permissionDenied")
            }

            Section("livetv.dvr.upcoming") {
                if store.upcomingRecordings.isEmpty {
                    Text("livetv.empty.recordings")
                }
                ForEach(store.upcomingRecordings) { recording in
                    upcomingRecordingRow(recording)
                }
            }
            Section("livetv.dvr.rules") {
                ForEach(store.recordingRules) { rule in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { selectedRule = rule } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.title)
                                Text(rule.modeTitle)
                                    .font(.cardMetadata)
                                    .foregroundStyle(.secondary)
                                if let library = rule.targetLibraryTitle {
                                    Label(library, systemImage: "rectangle.stack")
                                        .font(.cardMetadata)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if let libraryID = rule.targetLibraryID {
                            Button("livetv.dvr.openLibrary", systemImage: "rectangle.stack") { onOpenLibrary(libraryID)
                            }
                        }
                    }
                    .contextMenu {
                        Button("common.delete", role: .destructive) { delete(rule) }
                    }
                }
            }
            if store.dvr?.supportsCompletedRecordings == true {
                Section("livetv.dvr.completed") {
                    ForEach(store.completedRecordings) { recording in
                        Button {
                            if let media = recording.playableMedia {
                                onPlayRecording(media)
                            }
                        } label: {
                            recordingRow(recording)
                        }
                        .contextMenu {
                            if store.dvr?.canDeleteRecordings == true {
                                Button("common.delete", role: .destructive) { pendingRecordingDeletion = recording }
                            }
                        }
                    }
                }
            }
        }
    }

    private func recordingRow(_ recording: DVRRecording) -> some View {
        VStack(alignment: .leading) {
            Text(recording.title)
            HStack {
                if let channel = recording.channelTitle {
                    Text(channel)
                }
                if let start = recording.startDate {
                    Text(start, format: .dateTime.weekday().hour().minute())
                }
                Text(recording.status.localizedTitle)
            }
            .font(.cardMetadata)
            // Hierarchical: the row is a button, which turns white when focused on tvOS.
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func upcomingRecordingRow(_ recording: DVRRecording) -> some View {
        if store.dvr?.canManageRecordings == true {
            Button {
                requestCancellation(for: recording)
            } label: {
                recordingRow(recording)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("livetv.recording.cancel", role: .destructive) {
                    requestCancellation(for: recording)
                }
            }
        } else {
            recordingRow(recording)
        }
    }

    private func requestCancellation(for recording: DVRRecording) {
        guard store.dvr?.canManageRecordings == true else { return }
        pendingRecordingCancellation = recording
    }

    private func cancelPendingRecording() {
        guard let recording = pendingRecordingCancellation, let dvr = store.dvr else { return }
        pendingRecordingCancellation = nil
        Task {
            do {
                try await dvr.cancel(recordingID: recording.id)
                await store.refreshDVR()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                LiveTVErrorReporting.capture(error)
            }
        }
    }

    private func delete(_ rule: DVRRecordingRule) {
        guard let dvr = store.dvr else { return }
        Task {
            do {
                try await dvr.delete(ruleID: rule.id)
                await store.refreshDVR()
            } catch {
                LiveTVErrorReporting.capture(error)
            }
        }
    }
}

private extension DVRRecordingStatus {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .scheduled: "livetv.recording.status.scheduled"
        case .recording: "livetv.recording.status.recording"
        case .completed: "livetv.recording.status.completed"
        case .cancelled: "livetv.recording.status.cancelled"
        case .error: "livetv.recording.status.error"
        case .unknown: "livetv.recording.status.unknown"
        }
    }
}
