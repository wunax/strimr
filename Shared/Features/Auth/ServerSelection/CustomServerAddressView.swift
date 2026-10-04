import SwiftUI

struct CustomServerAddressView: View {
    @Bindable var model: CustomServerAddressModel
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
                            text: $model.address,
                        )
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .focused($isAddressFocused)
                        .onSubmit {
                            Task { await model.connect() }
                        }

                        Text("serverSelection.customAddress.description")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let error = model.error {
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
                    if model.canRemove {
                        removeButton
                    }
                    Spacer()
                    Button("common.actions.cancel") {
                        model.cancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)

                    Button {
                        Task { await model.connect() }
                    } label: {
                        confirmationLabel
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking)
                }
                .padding(16)
            }
            .frame(width: 520)
            .interactiveDismissDisabled(model.isWorking)
            .onAppear { isAddressFocused = true }
        }
    #endif

    #if os(tvOS)
        private var tvOSContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("serverSelection.customAddress.description")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("serverSelection.customAddress.field").font(.headline)
                        TextField(
                            "serverSelection.customAddress.placeholder",
                            text: $model.address,
                        )
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isAddressFocused)
                        .onSubmit {
                            guard !model.isWorking else { return }
                            Task { await model.connect() }
                        }
                    }

                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 32) {
                        Button {
                            Task { await model.connect() }
                        } label: {
                            confirmationLabel
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isWorking)

                        Button("common.actions.cancel") {
                            model.cancel()
                        }
                        .disabled(model.isWorking)

                        if model.canRemove {
                            removeButton
                        }
                    }
                    .padding(.top, 16)
                }
                .padding(32)
                .frame(maxWidth: 960, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .taskModalTitle("serverSelection.customAddress.title")
            .interactiveDismissDisabled(model.isWorking)
            .onAppear { isAddressFocused = true }
        }
    #endif

    private var platformForm: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "serverSelection.customAddress.placeholder",
                        text: $model.address,
                    )
                    .textContentType(.URL)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                        .autocorrectionDisabled()
                        .focused($isAddressFocused)
                        .onSubmit {
                            Task { await model.connect() }
                        }
                } header: {
                    Text("serverSelection.customAddress.field")
                } footer: {
                    Text("serverSelection.customAddress.description")
                }

                if let error = model.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if model.canRemove {
                    Section {
                        removeButton
                    }
                }
            }
            .navigationTitle("serverSelection.customAddress.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.actions.cancel") {
                        model.cancel()
                    }
                    .disabled(model.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await model.connect() }
                    } label: {
                        confirmationLabel
                    }
                    .disabled(model.isWorking)
                }
            }
            .interactiveDismissDisabled(model.isWorking)
            .onAppear { isAddressFocused = true }
        }
    }

    private var removeButton: some View {
        Button("serverSelection.customAddress.remove", role: .destructive) {
            Task { await model.removeAddress() }
        }
        .disabled(model.isWorking)
    }

    @ViewBuilder
    private var confirmationLabel: some View {
        if model.isWorking {
            ProgressView()
        } else {
            Text("serverSelection.customAddress.connect")
        }
    }
}
