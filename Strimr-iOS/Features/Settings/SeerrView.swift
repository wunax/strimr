import SwiftUI

@MainActor
struct SeerrView: View {
    @Bindable var viewModel: SeerrViewModel
    @State private var showingSetup = false
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        List {
            if viewModel.user == nil {
                Section("integrations.seerr.setup.title") {
                    Text("integrations.seerr.setup.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        showingSetup = true
                    } label: {
                        Label("integrations.seerr.setup.start", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .tint(.secondary)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else if let baseURL = viewModel.baseURLString {
                Section("integrations.seerr.server.title") {
                    LabeledContent("integrations.seerr.server.url.title") {
                        HStack(spacing: 8) {
                            Text(baseURL)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
            }

            if let user = viewModel.user {
                Section("integrations.seerr.account.title") {
                    LabeledContent("integrations.seerr.account.userId") {
                        Text("\(user.id)")
                    }
                }

                Section("integrations.seerr.quota.title") {
                    LabeledContent("integrations.seerr.quota.movies") {
                        Text(quotaSummary(viewModel.quota?.movie))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("integrations.seerr.quota.tv") {
                        Text(quotaSummary(viewModel.quota?.tv))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("integrations.seerr.settings.title") {
                    Toggle(
                        "integrations.seerr.settings.discoverTab",
                        isOn: Binding(
                            get: { settingsManager.interface.displaySeerrDiscoverTab },
                            set: { settingsManager.setDisplaySeerrDiscoverTab($0) },
                        ),
                    )
                }

                Section {
                    Button("integrations.seerr.actions.signOut", role: .destructive) {
                        viewModel.signOut()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("integrations.seerr.title")
        .alert("integrations.seerr.error.title", isPresented: $viewModel.isShowingError) {
            Button("common.actions.done") {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $showingSetup) {
            SeerrSetupView(viewModel: viewModel) {
                showingSetup = false
            }
        }
    }
}

private func quotaSummary(_ restriction: SeerrQuotaRestriction?) -> String {
    guard let restriction else {
        return String(localized: "integrations.seerr.quota.unavailable")
    }

    if restriction.limit == 0 {
        return String(localized: "integrations.seerr.quota.unlimited")
    }

    var parts: [String] = []

    if let used = restriction.used {
        parts.append(String(localized: "integrations.seerr.quota.used \(used)"))
    }

    if let remaining = restriction.remaining {
        parts.append(String(localized: "integrations.seerr.quota.remaining \(remaining)"))
    }

    if let limit = restriction.limit {
        parts.append(String(localized: "integrations.seerr.quota.limit \(limit)"))
    }

    if parts.isEmpty {
        return String(localized: "integrations.seerr.quota.unavailable")
    }

    return parts.joined(separator: " • ")
}

private enum SeerrSetupStep: Hashable {
    case server
    case method
    case local
}

@MainActor
private struct SeerrSetupView: View {
    @Bindable var viewModel: SeerrViewModel
    var onClose: () -> Void
    @State private var path: [SeerrSetupStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            SeerrServerStepView(viewModel: viewModel) {
                path.append(.method)
            }
            .navigationTitle("integrations.seerr.setup.title")
            .navigationDestination(for: SeerrSetupStep.self) { step in
                switch step {
                case .server:
                    EmptyView()
                case .method:
                    SeerrAuthMethodStepView(viewModel: viewModel) {
                        path.append(.local)
                    }
                case .local:
                    SeerrLocalAuthStepView(viewModel: viewModel)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.actions.cancel") {
                        onClose()
                    }
                }
            }
        }
        .onChange(of: viewModel.isLoggedIn) { _, newValue in
            if newValue {
                onClose()
            }
        }
    }
}

@MainActor
private struct SeerrServerStepView: View {
    @Bindable var viewModel: SeerrViewModel
    var onContinue: () -> Void

    var body: some View {
        List {
            Section("integrations.seerr.server.title") {
                TextField(
                    "integrations.seerr.server.url.title",
                    text: $viewModel.baseURLInput,
                    prompt: Text("integrations.seerr.server.url.placeholder"),
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    Task {
                        await viewModel.validateServer()
                        if viewModel.baseURLString != nil {
                            onContinue()
                        }
                    }
                } label: {
                    Label("integrations.seerr.server.save", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .tint(.secondary)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty || viewModel.isValidating)
            }
        }
        .listStyle(.insetGrouped)
    }
}

@MainActor
private struct SeerrAuthMethodStepView: View {
    @Bindable var viewModel: SeerrViewModel
    var onSelectLocal: () -> Void

    var body: some View {
        List {
            Section("integrations.seerr.setup.method.title") {
                VStack {
                    Button {
                        Task {
                            await viewModel.signInWithPlex()
                        }
                    } label: {
                        Label("integrations.seerr.login.plex", systemImage: "person.fill.checkmark")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .tint(.secondary)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!viewModel.isPlexAuthAvailable || viewModel.isAuthenticating)

                    Text("integrations.seerr.login.plex.connectedAccount")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !viewModel.isPlexAuthAvailable {
                        Text("integrations.seerr.login.plex.unavailable")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    Button {
                        onSelectLocal()
                    } label: {
                        Label("integrations.seerr.login.local", systemImage: "person.crop.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .tint(.secondary)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isAuthenticating)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("integrations.seerr.login.title")
    }
}

@MainActor
private struct SeerrLocalAuthStepView: View {
    @Bindable var viewModel: SeerrViewModel

    var body: some View {
        List {
            Section("integrations.seerr.login.local.title") {
                TextField("integrations.seerr.login.email", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("integrations.seerr.login.password", text: $viewModel.password)

                Button {
                    Task {
                        await viewModel.signInWithLocal()
                    }
                } label: {
                    Label("integrations.seerr.login.local", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .tint(.secondary)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty || viewModel.password.isEmpty || viewModel.isAuthenticating)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("integrations.seerr.login.local.title")
    }
}
