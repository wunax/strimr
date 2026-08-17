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
            Spacer(minLength: 0)

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
            .frame(maxWidth: authenticationContentMaxWidth)

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
                        viewModel.isBusy
                            || viewModel.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    )

                    Button {
                        Task { await viewModel.discoverServers() }
                    } label: {
                        HStack(spacing: 10) {
                            if viewModel.isDiscovering {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("jellyfin.auth.discovery.search")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .controlSize(.large)
                    .disabled(viewModel.isBusy)
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
                        viewModel.isBusy
                            || viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    )
                }
            }
            .frame(maxWidth: authenticationContentMaxWidth)

            if viewModel.step == .server, !viewModel.discoveredServers.isEmpty {
                discoveredServersList(viewModel)
            }

            if sessionManager.jellyfinHydrationError != nil {
                Button("common.actions.retry") {
                    Task { await sessionManager.retryJellyfinHydration() }
                }
            }

            Spacer(minLength: 0)

            bottomActions(viewModel)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bottomActions(_ viewModel: JellyfinAuthenticationViewModel) -> some View {
        VStack(spacing: buttonSpacing) {
            if viewModel.step == .credentials {
                Button {
                    viewModel.goBack()
                } label: {
                    Label("common.actions.back", systemImage: "chevron.left")
                }
                .disabled(viewModel.isLoading)
            }

            Button {
                Task { await sessionManager.requestProviderSelection() }
            } label: {
                Label("provider.change", systemImage: "chevron.left")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(maxWidth: authenticationContentMaxWidth)
    }

    private func discoveredServersList(_ viewModel: JellyfinAuthenticationViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.discoveredServers) { server in
                    Button {
                        Task { await viewModel.selectDiscoveredServer(server) }
                    } label: {
                        HStack(spacing: serverRowSpacing) {
                            Circle()
                                .fill(.brandPrimary.opacity(0.2))
                                .frame(width: serverIconSize, height: serverIconSize)
                                .overlay {
                                    Image(systemName: "server.rack")
                                        .foregroundStyle(.brandPrimary)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(server.url.absoluteString)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(serverRowPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isBusy)
                }
            }
        }
        #if os(tvOS)
            .scrollClipDisabled()
        #endif
        .frame(maxWidth: authenticationContentMaxWidth, maxHeight: discoveredServersMaxHeight)
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

    private var authenticationContentMaxWidth: CGFloat {
        #if os(tvOS)
            640
        #else
            520
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

    private var serverIconSize: CGFloat {
        #if os(tvOS)
            64
        #else
            44
        #endif
    }

    private var serverRowSpacing: CGFloat {
        #if os(tvOS)
            28
        #else
            12
        #endif
    }

    private var serverRowPadding: CGFloat {
        #if os(tvOS)
            24
        #else
            16
        #endif
    }

    private var discoveredServersMaxHeight: CGFloat {
        #if os(tvOS)
            360
        #else
            240
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
