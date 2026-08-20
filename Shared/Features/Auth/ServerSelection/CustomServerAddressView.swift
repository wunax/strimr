import SwiftUI

struct CustomServerAddressView: View {
    @Bindable var viewModel: ServerSelectionViewModel
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        #if os(macOS)
            macOSContent
        #elseif os(tvOS)
            tvOSContent
        #else
            platformForm
        #endif
    }

    #if os(macOS)
        private var macOSContent: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("serverSelection.customAddress.title")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 8) {
                        Text("serverSelection.customAddress.field")
                            .font(.headline)

                        TextField(
                            "serverSelection.customAddress.placeholder",
                            text: $viewModel.customAddress,
                        )
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .focused($isAddressFocused)
                        .onSubmit {
                            Task { await viewModel.connectWithCustomAddress() }
                        }

                        Text("serverSelection.customAddress.description")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let error = viewModel.customAddressError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)

                Divider()

                HStack(spacing: 12) {
                    Spacer()
                    Button("common.actions.cancel") {
                        viewModel.dismissCustomAddress()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(viewModel.isSelecting)

                    Button {
                        Task { await viewModel.connectWithCustomAddress() }
                    } label: {
                        confirmationLabel
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isSelecting)
                }
                .padding(16)
            }
            .frame(width: 520)
            .interactiveDismissDisabled(viewModel.isSelecting)
            .onAppear { isAddressFocused = true }
        }
    #endif

    #if os(tvOS)
        private var tvOSContent: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField(
                            "serverSelection.customAddress.placeholder",
                            text: $viewModel.customAddress,
                        )
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .focused($isAddressFocused)
                        .onSubmit {
                            Task { await viewModel.connectWithCustomAddress() }
                        }

                        Button {
                            Task { await viewModel.connectWithCustomAddress() }
                        } label: {
                            confirmationLabel
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isSelecting)
                    } header: {
                        Text("serverSelection.customAddress.field")
                    } footer: {
                        Text("serverSelection.customAddress.description")
                    }

                    if let error = viewModel.customAddressError {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle("serverSelection.customAddress.title")
                .interactiveDismissDisabled(viewModel.isSelecting)
                .onAppear { isAddressFocused = true }
            }
        }
    #endif

    private var platformForm: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "serverSelection.customAddress.placeholder",
                        text: $viewModel.customAddress,
                    )
                    .textContentType(.URL)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                        .autocorrectionDisabled()
                        .focused($isAddressFocused)
                        .onSubmit {
                            Task { await viewModel.connectWithCustomAddress() }
                        }
                } header: {
                    Text("serverSelection.customAddress.field")
                } footer: {
                    Text("serverSelection.customAddress.description")
                }

                if let error = viewModel.customAddressError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("serverSelection.customAddress.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.actions.cancel") {
                        viewModel.dismissCustomAddress()
                    }
                    .disabled(viewModel.isSelecting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await viewModel.connectWithCustomAddress() }
                    } label: {
                        confirmationLabel
                    }
                    .disabled(viewModel.isSelecting)
                }
            }
            .interactiveDismissDisabled(viewModel.isSelecting)
            .onAppear { isAddressFocused = true }
        }
    }

    @ViewBuilder
    private var confirmationLabel: some View {
        if viewModel.isSelecting {
            ProgressView()
        } else {
            Text("serverSelection.customAddress.connect")
        }
    }
}
