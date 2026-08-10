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
        VStack(spacing: contentSpacing) {
            VStack(spacing: headerSpacing) {
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

            VStack(spacing: fieldSpacing) {
                if viewModel.step == .server {
                    TextField("jellyfin.auth.server.placeholder", text: Bindable(viewModel).serverURL)
                        .textContentType(.URL)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                        .onSubmit { Task { await viewModel.validateServer() } }
                        .jellyfinAuthenticationFieldStyle()
                } else {
                    TextField("jellyfin.auth.username", text: Bindable(viewModel).username)
                        .textContentType(.username)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #endif
                        .jellyfinAuthenticationFieldStyle()
                    SecureField("jellyfin.auth.password", text: Bindable(viewModel).password)
                        .textContentType(.password)
                        .onSubmit { Task { await viewModel.signIn() } }
                        .jellyfinAuthenticationFieldStyle()
                }
            }
            .frame(maxWidth: 520)

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: buttonSpacing) {
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
                        Label("common.actions.back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
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
        .padding(.vertical, 4)
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

    private var contentSpacing: CGFloat {
        #if os(tvOS)
            40
        #else
            24
        #endif
    }

    private var headerSpacing: CGFloat {
        #if os(tvOS)
            20
        #else
            12
        #endif
    }

    private var fieldSpacing: CGFloat {
        #if os(tvOS)
            24
        #else
            14
        #endif
    }

    private var buttonSpacing: CGFloat {
        #if os(tvOS)
            24
        #else
            12
        #endif
    }
}

private extension View {
    @ViewBuilder
    func jellyfinAuthenticationFieldStyle() -> some View {
        #if os(tvOS)
            self
                .textFieldStyle(.automatic)
                .controlSize(.large)
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
