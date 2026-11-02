import SwiftUI

struct ItemSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: ItemSettingsViewModel

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        TaskModalNavigationView {
            content
                .taskModalTitle("media.advancedSettings.title")
                .taskModalActions {
                    Button("common.actions.done") { dismiss() }
                } actions: {
                    EmptyView()
                }
                .alert(item: $bindableViewModel.failure) { failure in
                    Alert(
                        title: Text("media.advancedSettings.error"),
                        message: Text(failure.message),
                        dismissButton: .default(Text("common.actions.done")),
                    )
                }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 440)
        #endif
        // Closing while a choice is saved would skip the reload of the card that opened the screen.
        .interactiveDismissDisabled(viewModel.updatingSettingID != nil)
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            } description: {
                Text("common.errors.tryAgainLater")
            } actions: {
                Button("common.actions.retry") {
                    Task { await viewModel.load() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let settings = viewModel.settings {
            if settings.isEmpty {
                ContentUnavailableView("media.advancedSettings.empty", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                form(settings)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func form(_ settings: [ItemSetting]) -> some View {
        Form {
            ForEach(settings) { setting in
                Section {
                    Picker(selection: selection(for: setting)) {
                        ForEach(setting.options, id: \.value) { option in
                            Text(verbatim: option.label).tag(option.value)
                        }
                    } label: {
                        Text(verbatim: setting.label)
                    }
                    // tvOS modals have no navigation stack for the default picker to push its choices on.
                    .pickerStyle(.menu)
                    .disabled(viewModel.updatingSettingID != nil)
                } footer: {
                    if let summary = setting.summary {
                        Text(verbatim: summary)
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private func selection(for setting: ItemSetting) -> Binding<String> {
        Binding(
            get: { setting.value },
            set: { value in
                Task { await viewModel.update(setting, to: value) }
            },
        )
    }
}
