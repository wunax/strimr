import SwiftUI

extension DVRRecordingRule {
    var modeTitle: LocalizedStringKey {
        isSeries ? "livetv.recording.rule.series" : "livetv.recording.rule.episode"
    }
}

struct DVRRuleEditView: View {
    let rule: DVRRecordingRule
    let dvr: (any MediaDVRService)?
    let onChanged: () async -> Void
    private let baselineValues: [String: String]

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String]
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(rule: DVRRecordingRule, dvr: (any MediaDVRService)?, onChanged: @escaping () async -> Void) {
        self.rule = rule
        self.dvr = dvr
        self.onChanged = onChanged
        let initialValues = Dictionary(uniqueKeysWithValues: rule.options.map { option in
            (option.id, rule.optionValues[option.id] ?? option.resolvedValue)
        })
        baselineValues = initialValues
        _values = State(initialValue: initialValues)
    }

    var body: some View {
        TaskModalNavigationView {
            Form {
                Section {
                    Text(rule.title)
                        .font(.tileTitle)
                        .foregroundStyle(.textPrimary)
                    HStack {
                        Label("livetv.recording.mode", systemImage: "record.circle")
                        Spacer()
                        Text(rule.modeTitle)
                            .foregroundStyle(.textSecondary)
                    }
                    if let library = rule.targetLibraryTitle {
                        HStack {
                            Label("livetv.recording.library", systemImage: "rectangle.stack")
                            Spacer()
                            Text(library)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }
                if rule.options.isEmpty {
                    Section {
                        Text("livetv.dvr.noEditableOptions")
                            .foregroundStyle(.textSecondary)
                    }
                } else {
                    Section("livetv.dvr.options") {
                        ForEach(rule.options) { option in
                            optionEditor(option)
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .taskModalTitle("livetv.dvr.editRule")
            .taskModalActions {
                Button("common.done") { save() }
                    .disabled(isSaving)
            } actions: {
                Button("common.cancel") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func optionEditor(_ option: DVRRecordingOption) -> some View {
        switch option.kind {
        case .toggle:
            Toggle(isOn: Binding(
                get: { isTruthy(values[option.id] ?? option.resolvedValue) },
                set: { values[option.id] = String($0) },
            )) {
                optionLabel(option)
            }
        case let .choice(choices):
            let currentValue = values[option.id] ?? option.resolvedValue
            let choices = choices + (choices.contains(where: { $0.id == currentValue })
                ? []
                : [DVRRecordingOptionChoice(id: currentValue, title: currentValue)])
            Picker(selection: valueBinding(option)) {
                ForEach(choices) { choice in
                    Text(choice.title).tag(choice.id)
                }
            } label: {
                optionLabel(option)
            }
        case .integer, .text:
            VStack(alignment: .leading, spacing: 6) {
                optionLabel(option)
                TextField(
                    option.title,
                    text: valueBinding(option),
                )
                .multilineTextAlignment(.leading)
            }
        }
    }

    private func optionLabel(_ option: DVRRecordingOption) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(option.title)
            if let summary = option.summary, !summary.isEmpty {
                Text(summary)
                    .font(.cardMetadata)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func valueBinding(_ option: DVRRecordingOption) -> Binding<String> {
        Binding(
            get: { values[option.id] ?? option.resolvedValue },
            set: { values[option.id] = $0 },
        )
    }

    private func isTruthy(_ value: String) -> Bool {
        ["true", "1", "yes"].contains(value.lowercased())
    }

    private func save() {
        guard let dvr else { return }
        let changedValues = values.filter { key, value in baselineValues[key] != value }
        guard !changedValues.isEmpty else {
            dismiss()
            return
        }
        isSaving = true
        Task {
            do {
                try await dvr.update(rule: rule, options: changedValues)
                guard !Task.isCancelled else { return }
                await onChanged()
                dismiss()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                LiveTVErrorReporting.capture(error)
                errorMessage = String(localized: "livetv.dvr.updateError")
                isSaving = false
            }
        }
    }
}
