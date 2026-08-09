import SwiftUI

struct JellyfinAuthenticationView: View {
    @Environment(JellyfinAPIContext.self) private var context
    @Environment(SessionManager.self) private var sessionManager
    @State private var viewModel: JellyfinAuthenticationViewModel?

    var body: some View {
        Group {
            if let viewModel {
                authenticationForm(viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = JellyfinAuthenticationViewModel(
                    context: context,
                    sessionManager: sessionManager,
                )
            }
        }
    }

    private func authenticationForm(_ viewModel: JellyfinAuthenticationViewModel) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.brandPrimary)
                if viewModel.step == .server {
                    Text("jellyfin.auth.server.title")
                        .font(.largeTitle.bold())
                    Text("jellyfin.auth.server.subtitle")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("jellyfin.auth.credentials.title")
                        .font(.largeTitle.bold())
                    Text("jellyfin.auth.credentials.subtitle \(viewModel.serverName)")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: 14) {
                if viewModel.step == .server {
                    TextField("jellyfin.auth.server.placeholder", text: Bindable(viewModel).serverURL)
                        .textContentType(.URL)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                        .onSubmit { Task { await viewModel.validateServer() } }
                } else {
                    TextField("jellyfin.auth.username", text: Bindable(viewModel).username)
                        .textContentType(.username)
                    SecureField("jellyfin.auth.password", text: Bindable(viewModel).password)
                        .textContentType(.password)
                        .onSubmit { Task { await viewModel.signIn() } }
                }
            }
            .jellyfinAuthenticationFieldStyle()
            .frame(maxWidth: 520)

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                if viewModel.step == .credentials {
                    Button("common.actions.back") { viewModel.goBack() }
                        .buttonStyle(.bordered)
                }
                if viewModel.step == .server {
                    Button("common.actions.continue") {
                        Task { await viewModel.validateServer() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading)
                } else {
                    Button("jellyfin.auth.signIn") {
                        Task { await viewModel.signIn() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading)
                }
            }

            if viewModel.isLoading {
                ProgressView()
            }

            if sessionManager.jellyfinHydrationError != nil {
                Button("common.actions.retry") {
                    Task { await sessionManager.retryJellyfinHydration() }
                }
            }

            Button("provider.change") {
                Task { await sessionManager.changeProvider() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    @ViewBuilder
    func jellyfinAuthenticationFieldStyle() -> some View {
        #if os(tvOS)
            self
        #else
            textFieldStyle(.roundedBorder)
        #endif
    }
}
