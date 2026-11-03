import SwiftUI

enum LiveTVProgramRecordingAction {
    case cancelRecording(String)
    case deleteSeriesRule(String)
}

struct LiveTVProgramDetailView: View {
    let program: LiveTVProgram
    let channel: LiveTVChannel?
    let dvr: (any MediaDVRService)?
    let supportsWatchFromStart: Bool
    let onWatch: () -> Void
    let onWatchFromStart: () -> Void
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var template: DVRRecordingTemplate?
    @State private var recordsSeries = false
    @State private var optionValues: [String: String] = [:]
    @State private var targetLibraryID: String?
    @State private var errorMessage: String?
    @State private var isSubmittingRecording = false
    @State private var pendingProgramRecordingAction: LiveTVProgramRecordingAction?

    private var selectedRecordingMode: DVRRecordingMode {
        recordsSeries ? .series : .single
    }

    private var selectedRecordingTemplate: DVRRecordingModeTemplate? {
        template?.template(for: selectedRecordingMode)
    }

    private var recordingActionConfirmationTitle: LocalizedStringKey {
        switch pendingProgramRecordingAction {
        case .deleteSeriesRule:
            "livetv.recording.stopSeries.confirm"
        case .cancelRecording, nil:
            "livetv.recording.cancel.confirm"
        }
    }

    var body: some View {
        TaskModalNavigationView {
            Form {
                Section {
                    Text(program.title)
                        .font(.tileTitle)
                        .foregroundStyle(.textPrimary)
                    if let channel {
                        Text(channel.displayTitle)
                            .font(.facts)
                            .foregroundStyle(.textSecondary)
                    }
                    Text(program.startDate.formatted(date: .abbreviated, time: .shortened) + " – " + program.endDate
                        .formatted(
                            date: .omitted,
                            time: .shortened,
                        ))
                    if let summary = program.summary {
                        Text(summary)
                        #if os(tvOS)
                            .padding(16)
                            .modifier(TVModalReadingFocus())
                        #endif
                    }
                    if program.isCurrentlyAiring {
                        ProgressView(value: program.progress)
                    }
                }
                if let template, let modeTemplate = selectedRecordingTemplate, !program.isScheduledForRecording {
                    if !template.libraries.isEmpty {
                        Picker("livetv.recording.library", selection: $targetLibraryID) {
                            ForEach(template.libraries) { Text($0.title).tag(Optional($0.id)) }
                        }
                    }
                    if template.supportsSingle, template.supportsSeries {
                        Picker("livetv.recording.mode", selection: Binding(
                            get: { recordsSeries },
                            set: { selectRecordingMode(series: $0) },
                        )) {
                            Text("livetv.record").tag(false)
                            Text("livetv.recordSeries").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    ForEach(modeTemplate.options) { option in
                        optionEditor(option)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .taskModalTitle("livetv.program.details")
            .taskModalActions(grouped: true) {
                if program.isCurrentlyAiring {
                    Button("livetv.watchLive", action: onWatch)
                }
            } actions: {
                if program.isCurrentlyAiring, supportsWatchFromStart {
                    Button("livetv.watchFromStart", action: onWatchFromStart)
                }
                if dvr?.canManageRecordings == true {
                    if let recordingID = program.recordingID {
                        Button("livetv.stopRecord", role: .destructive) {
                            pendingProgramRecordingAction = .cancelRecording(recordingID)
                        }
                        .disabled(isSubmittingRecording)
                    }
                    if let seriesRecordingID = program.seriesRecordingID {
                        Button("livetv.recording.stopSeries", role: .destructive) {
                            pendingProgramRecordingAction = .deleteSeriesRule(seriesRecordingID)
                        }
                        .disabled(isSubmittingRecording)
                    }
                    if !program.isScheduledForRecording, selectedRecordingTemplate != nil {
                        Button {
                            schedule(series: recordsSeries)
                        } label: {
                            Text(recordsSeries ? "livetv.recordSeries" : "livetv.record")
                        }
                        .disabled(isSubmittingRecording)
                    }
                }
                Button("common.done") { dismiss() }
            }
            .confirmationDialog(
                recordingActionConfirmationTitle,
                isPresented: Binding(
                    get: { pendingProgramRecordingAction != nil },
                    set: {
                        if !$0 {
                            pendingProgramRecordingAction = nil
                        }
                    },
                ),
                titleVisibility: .visible,
            ) {
                switch pendingProgramRecordingAction {
                case let .cancelRecording(recordingID):
                    Button("livetv.recording.cancel", role: .destructive) {
                        submitRecordingAction(.cancelRecording(recordingID))
                    }
                case let .deleteSeriesRule(ruleID):
                    Button("livetv.recording.stopSeries", role: .destructive) {
                        submitRecordingAction(.deleteSeriesRule(ruleID))
                    }
                case nil:
                    EmptyView()
                }
            } message: {
                Text(program.title)
            }
            .task {
                guard !program.isScheduledForRecording, let dvr, dvr.canManageRecordings else { return }
                do {
                    let value = try await dvr.recordingTemplate(for: program)
                    template = value
                    let initialMode = value.preferredMode ?? (value.supportsSingle ? .single : .series)
                    selectRecordingMode(series: initialMode == .series)
                } catch {
                    guard !Task.isCancelled, !error.isCancellation else { return }
                    LiveTVErrorReporting.capture(error)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func selectRecordingMode(series: Bool) {
        recordsSeries = series
        guard let modeTemplate = selectedRecordingTemplate else {
            optionValues = [:]
            targetLibraryID = nil
            return
        }
        optionValues = Dictionary(uniqueKeysWithValues: modeTemplate.options.map { ($0.id, $0.defaultValue) })
        targetLibraryID = modeTemplate.defaultLibraryID
    }

    @ViewBuilder private func optionEditor(_ option: DVRRecordingOption) -> some View {
        switch option.kind {
        case .toggle:
            Toggle(option.title, isOn: Binding(
                get: { optionValues[option.id] == "true" },
                set: { optionValues[option.id] = String($0) },
            ))
        case let .choice(choices):
            Picker(option.title, selection: valueBinding(option)) {
                ForEach(choices) { Text($0.title).tag($0.id) }
            }
        case .integer, .text:
            VStack(alignment: .leading, spacing: 6) {
                Text(option.title)
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(text: valueBinding(option)) {
                    Text(option.title)
                }
                .multilineTextAlignment(.leading)
            }
        }
    }

    private func valueBinding(_ option: DVRRecordingOption) -> Binding<String> {
        Binding(get: { optionValues[option.id] ?? option.defaultValue }, set: { optionValues[option.id] = $0 })
    }

    private func schedule(series: Bool) {
        guard let dvr else { return }
        recordsSeries = series
        isSubmittingRecording = true
        Task {
            do {
                try await dvr.schedule(.init(
                    program: program,
                    recordsSeries: series,
                    targetLibraryID: targetLibraryID,
                    options: optionValues,
                ))
                await onChanged()
                dismiss()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                switch error {
                case let error as JellyfinAPIError where error == .recordingConflict:
                    break
                default:
                    LiveTVErrorReporting.capture(error)
                }
                errorMessage = error.localizedDescription
                isSubmittingRecording = false
            }
        }
    }

    private func submitRecordingAction(_ action: LiveTVProgramRecordingAction) {
        guard let dvr else { return }
        pendingProgramRecordingAction = nil
        isSubmittingRecording = true
        Task {
            do {
                switch action {
                case let .cancelRecording(recordingID):
                    guard !recordingID.isEmpty else {
                        isSubmittingRecording = false
                        return
                    }
                    try await dvr.cancel(recordingID: recordingID)
                case let .deleteSeriesRule(ruleID):
                    guard !ruleID.isEmpty else {
                        isSubmittingRecording = false
                        return
                    }
                    try await dvr.delete(ruleID: ruleID)
                }
                await onChanged()
                dismiss()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                LiveTVErrorReporting.capture(error)
                errorMessage = error.localizedDescription
                isSubmittingRecording = false
            }
        }
    }
}
