import SwiftUI

/// Library, padding, retention and the other server options of a recording, before scheduling it.
struct LiveTVRecordOptionsView: View {
    let program: LiveTVProgram
    let template: DVRRecordingTemplate
    @Bindable var store: LiveTVStore

    @Environment(\.dismiss) private var dismiss
    @State private var recordsSeries = false
    @State private var optionValues: [String: String] = [:]
    @State private var targetLibraryID: String?
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var modeTemplate: DVRRecordingModeTemplate? {
        template.template(for: recordsSeries ? .series : .single)
    }

    var body: some View {
        TaskModalNavigationView {
            Form {
                if template.supportsSingle, template.supportsSeries {
                    Picker("livetv.recording.mode", selection: Binding(
                        get: { recordsSeries },
                        set: { selectMode(series: $0) },
                    )) {
                        Text("livetv.record").tag(false)
                        Text("livetv.recordSeries").tag(true)
                    }
                    #if !os(tvOS)
                    .pickerStyle(.segmented)
                    #endif
                }
                if !template.libraries.isEmpty {
                    Picker("livetv.recording.library", selection: $targetLibraryID) {
                        ForEach(template.libraries) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
                if let modeTemplate {
                    ForEach(modeTemplate.options) { option in
                        optionEditor(option)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .taskModalTitle("livetv.recording.options")
            .taskModalActions {
                Button("livetv.record") { schedule() }
                    .disabled(isSubmitting || modeTemplate == nil)
            } actions: {
                Button("common.cancel") { dismiss() }
            }
            .onAppear {
                let mode = template.preferredMode ?? (template.supportsSingle ? .single : .series)
                selectMode(series: mode == .series)
            }
        }
    }

    private func selectMode(series: Bool) {
        recordsSeries = series
        optionValues = Dictionary(
            (modeTemplate?.options ?? []).map { ($0.id, $0.defaultValue) },
            uniquingKeysWith: { first, _ in first },
        )
        targetLibraryID = modeTemplate?.defaultLibraryID
    }

    @ViewBuilder
    private func optionEditor(_ option: DVRRecordingOption) -> some View {
        switch option.kind {
        case .toggle:
            Toggle(option.title, isOn: Binding(
                get: { ["true", "1", "yes"].contains(optionValues[option.id]?.lowercased() ?? "") },
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
                    .foregroundStyle(.secondary)
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

    private func schedule() {
        isSubmitting = true
        Task {
            do {
                try await store.record(
                    program,
                    series: recordsSeries,
                    libraryID: targetLibraryID,
                    options: optionValues,
                )
                dismiss()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                if (error as? JellyfinAPIError) != .recordingConflict {
                    LiveTVErrorReporting.capture(error)
                }
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
