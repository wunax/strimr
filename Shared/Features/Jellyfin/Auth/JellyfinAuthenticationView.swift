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
            VStack(spacing: 12) {
                Image("jellyfin_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: logoMaxWidth, maxHeight: logoMaxHeight)
                    .accessibilityHidden(true)

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
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #endif
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

            VStack(spacing: 12) {
                if viewModel.step == .server {
                    Button {
                        Task { await viewModel.validateServer() }
                    } label: {
                        primaryButtonLabel("common.actions.continue", isLoading: viewModel.isLoading)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .controlSize(.large)
                    .tint(.brandPrimary)
                    .disabled(
                        viewModel.isLoading
                            || viewModel.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    )
                } else {
                    Button {
                        Task { await viewModel.signIn() }
                    } label: {
                        primaryButtonLabel("jellyfin.auth.signIn", isLoading: viewModel.isLoading)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .controlSize(.large)
                    .tint(.brandPrimary)
                    .disabled(
                        viewModel.isLoading
                            || viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    )

                    Button {
                        viewModel.goBack()
                    } label: {
                        Text("common.actions.back")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .controlSize(.large)
                    .disabled(viewModel.isLoading)
                }
            }
            .frame(maxWidth: 520)

            if sessionManager.jellyfinHydrationError != nil {
                Button("common.actions.retry") {
                    Task { await sessionManager.retryJellyfinHydration() }
                }
            }

            Button {
                Task { await sessionManager.changeProvider() }
            } label: {
                Label("provider.change", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func primaryButtonLabel(
        _ title: LocalizedStringKey,
        isLoading: Bool,
    ) -> some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(title)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var logoMaxWidth: CGFloat {
        #if os(tvOS)
            300
        #else
            240
        #endif
    }

    private var logoMaxHeight: CGFloat {
        #if os(tvOS)
            96
        #else
            72
        #endif
    }
}

private extension View {
    @ViewBuilder
    func jellyfinAuthenticationFieldStyle() -> some View {
        #if os(tvOS)
            self
                .textFieldStyle(.plain)
                .padding(.horizontal, 20)
                .frame(minHeight: 72)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14))
                }
        #else
            self
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2))
                }
        #endif
    }
}
