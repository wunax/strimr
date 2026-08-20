import SwiftUI

struct CustomServerAddressView: View {
    @Bindable var viewModel: ServerSelectionViewModel
    @FocusState private var isAddressFocused: Bool

    var body: some View {
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
                        if viewModel.isSelecting {
                            ProgressView()
                        } else {
                            Text("serverSelection.customAddress.connect")
                        }
                    }
                    .disabled(viewModel.isSelecting)
                }
            }
            .interactiveDismissDisabled(viewModel.isSelecting)
            .onAppear { isAddressFocused = true }
        }
    }
}
