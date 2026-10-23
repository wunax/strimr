import SwiftUI

struct JellyfinAuthenticationView: View {
    @State private var viewModel: JellyfinAuthenticationViewModel

    init(viewModel: JellyfinAuthenticationViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        authenticationForm(viewModel)
            .onDisappear { viewModel.cancelQuickConnect() }
    }

    private func authenticationForm(_ viewModel: JellyfinAuthenticationViewModel) -> some View {
        VStack(spacing: contentSpacing) {
            Spacer(minLength: 0)

            VStack(spacing: headerSpacing) {
                Image("Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: appLogoSize, height: appLogoSize)
                    .clipShape(RoundedRectangle(cornerRadius: appLogoCornerRadius, style: .continuous))
                    .accessibilityHidden(true)

                if viewModel.step == .server {
                    Text("jellyfin.auth.server.title")
                        .font(.heroTitle)
                        .foregroundStyle(.textPrimary)
                    Text("jellyfin.auth.server.subtitle")
                        .font(.bodyText)
                        .foregroundStyle(.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("jellyfin.auth.credentials.title")
                        .font(.heroTitle)
                        .foregroundStyle(.textPrimary)
                    Text("jellyfin.auth.credentials.subtitle \(viewModel.serverName)")
                        .font(.bodyText)
                        .foregroundStyle(.textSecondary)
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
                    .font(.facts)
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
                    .actionButtonStyle(.primary)
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
                    .actionButtonStyle(.secondary)
                    .disabled(viewModel.isBusy)
                } else {
                    Button {
                        Task { await viewModel.signIn() }
                    } label: {
                        primaryButtonLabel("jellyfin.auth.signIn", isLoading: viewModel.isLoading)
                    }
                    .actionButtonStyle(.primary)
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

            if viewModel.step == .credentials, viewModel.isQuickConnectAvailable {
                quickConnect(viewModel)
                    .frame(maxWidth: authenticationContentMaxWidth)
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
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(maxWidth: authenticationContentMaxWidth)
    }

    @ViewBuilder
    private func quickConnect(_ viewModel: JellyfinAuthenticationViewModel) -> some View {
        if let code = viewModel.quickConnectCode {
            VStack(spacing: 8) {
                Text("jellyfin.auth.quickConnect.instructions")
                    .font(.bodyText)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
                Text(code)
                    .font(.system(.largeTitle, design: .monospaced).bold())
                    .foregroundStyle(.textPrimary)
                #if !os(tvOS)
                    .textSelection(.enabled)
                #endif
                Button("common.actions.cancel") { viewModel.cancelQuickConnect() }
            }
        } else {
            Button {
                viewModel.startQuickConnect()
            } label: {
                Label("jellyfin.auth.quickConnect.button", systemImage: "qrcode")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .actionButtonStyle(.secondary)
            .disabled(viewModel.isBusy)
        }
    }

    private func discoveredServersList(_ viewModel: JellyfinAuthenticationViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.discoveredServers) { server in
                    Button {
                        Task { await viewModel.selectDiscoveredServer(server) }
                    } label: {
                        HStack(spacing: serverRowSpacing) {
                            // Hierarchical styles: the focused plain button turns white on tvOS.
                            Circle()
                                .fill(.secondary.opacity(0.2))
                                .frame(width: serverIconSize, height: serverIconSize)
                                .overlay {
                                    Image(systemName: "server.rack")
                                        .foregroundStyle(.secondary)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .font(.rowTitle)
                                    .foregroundStyle(.primary)
                                Text(server.url.absoluteString)
                                    .font(.facts)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(serverRowPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            .surfaceSubtle,
                            in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous),
                        )
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

    private var appLogoSize: CGFloat {
        #if os(tvOS)
            192
        #else
            128
        #endif
    }

    private var authenticationContentMaxWidth: CGFloat {
        #if os(tvOS)
            640
        #else
            520
        #endif
    }

    private var appLogoCornerRadius: CGFloat {
        #if os(tvOS)
            40
        #else
            28
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
    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MediaArtworkMetrics.compactCornerRadius, style: .continuous)
    }

    @ViewBuilder
    func jellyfinAuthenticationFieldStyle() -> some View {
        #if os(tvOS)
            textFieldStyle(.automatic)
                .controlSize(.large)
        #else
            textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(.surfaceSubtle, in: fieldShape)
                .overlay {
                    fieldShape.stroke(.strokeSubtle)
                }
        #endif
    }
}
