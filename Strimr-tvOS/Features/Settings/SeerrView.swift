import SwiftUI

@MainActor
struct SeerrView: View {
    @Bindable var viewModel: SeerrViewModel
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            SettingsScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if viewModel.user == nil {
                        setupCard
                    }

                    if let baseURL = viewModel.baseURLString {
                        serverCard(baseURL)
                    }

                    if let user = viewModel.user {
                        accountCard(user)
                        quotaCard
                        settingsCard
                        signOutCard
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
        }
        .modifier(SeerrSettingsErrorPresentation(viewModel: viewModel))
    }

    private var setupCard: some View {
        SeerrCard(title: "integrations.seerr.setup.title") {
            Text("integrations.seerr.setup.description")
                .foregroundStyle(.secondary)

            SettingsLink(title: "integrations.seerr.server.title") {
                SeerrSetupView(viewModel: viewModel)
            } label: {
                Label("integrations.seerr.setup.start", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .settingsFocus("seerrSetup", isDefault: true)
            .tint(.brandPrimary)
        }
    }

    private func serverCard(_ baseURL: String) -> some View {
        SeerrCard(title: "integrations.seerr.server.title") {
            infoRow("integrations.seerr.server.url.title", value: baseURL)
        }
    }

    private func accountCard(_ user: SeerrUser) -> some View {
        SeerrCard(title: "integrations.seerr.account.title") {
            infoRow("integrations.seerr.account.userId", value: "\(user.id)")
        }
    }

    private var quotaCard: some View {
        SeerrCard(title: "integrations.seerr.quota.title") {
            infoRow(
                "integrations.seerr.quota.movies",
                value: quotaSummary(viewModel.quota?.movie),
            )
            infoRow(
                "integrations.seerr.quota.tv",
                value: quotaSummary(viewModel.quota?.tv),
            )
        }
    }

    private var settingsCard: some View {
        SeerrCard(title: "integrations.seerr.settings.title") {
            Toggle(
                "integrations.seerr.settings.discoverTab",
                isOn: Binding(
                    get: { settingsManager.interface.displaySeerrDiscoverTab },
                    set: { settingsManager.setDisplaySeerrDiscoverTab($0) },
                ),
            )
            .settingsFocus("seerrDiscover", isDefault: true)
        }
    }

    private var signOutCard: some View {
        SeerrCard {
            Button("integrations.seerr.actions.signOut", role: .destructive) {
                viewModel.signOut()
            }
            .buttonStyle(.bordered)
            .settingsFocus("seerrSignOut")
        }
    }

    private func infoRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
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

private struct SeerrCard<Content: View>: View {
    let title: LocalizedStringKey?
    let content: Content

    init(title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum SeerrSetupStep: Hashable {
    case server
    case method
    case local
    case jellyfin

    var titleKey: LocalizedStringKey {
        switch self {
        case .server:
            "integrations.seerr.server.title"
        case .method:
            "integrations.seerr.setup.method.title"
        case .local:
            "integrations.seerr.login.local.title"
        case .jellyfin:
            "integrations.seerr.login.jellyfin"
        }
    }
}

@MainActor
private struct SeerrSetupView: View {
    @Bindable var viewModel: SeerrViewModel
    @Environment(SettingsNavigation.self) private var navigation
    @Environment(\.settingsFocusContext) private var focusContext
    var step: SeerrSetupStep = .server

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                stepContent
            }
            .padding(20)
        }

        .modifier(SeerrSettingsErrorPresentation(viewModel: viewModel))
        .onChange(of: viewModel.isLoggedIn, initial: true) { _, newValue in
            if newValue {
                navigation.finishSeerrSetup()
            }
        }
        .onChange(of: viewModel.baseURLString, initial: true) { _, newValue in
            if newValue == nil, step != .server {
                navigation.restartSeerrSetup()
            }
        }
    }

    private func showStep(_ step: SeerrSetupStep) {
        // Validation can finish after the user changes category or leaves this page.
        guard navigation.category == .integrations,
              !navigation.sidebarFocused,
              navigation.pageID == focusContext?.pageID else { return }
        navigation.push(step.titleKey) {
            SeerrSetupView(viewModel: viewModel, step: step)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .server:
            SeerrServerStepView(viewModel: viewModel) {
                showStep(.method)
            }
        case .method:
            SeerrAuthMethodStepView(
                viewModel: viewModel,
                onSelectLocal: { showStep(.local) },
                onSelectJellyfin: { showStep(.jellyfin) },
            )
        case .local:
            SeerrLocalAuthStepView(viewModel: viewModel)
        case .jellyfin:
            SeerrJellyfinAuthStepView(viewModel: viewModel)
        }
    }
}

@MainActor
private struct SeerrServerStepView: View {
    @Bindable var viewModel: SeerrViewModel
    var onContinue: () -> Void

    var body: some View {
        SettingsScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SeerrCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("integrations.seerr.server.url.title")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        TextField(
                            "integrations.seerr.server.url.title",
                            text: $viewModel.baseURLInput,
                            prompt: Text("integrations.seerr.server.url.placeholder").foregroundColor(.gray),
                        )
                        .settingsFocus("input", isDefault: true)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            Task {
                                await viewModel.validateServer()
                                if viewModel.baseURLString != nil {
                                    onContinue()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isValidating {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("integrations.seerr.server.save")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .settingsFocus("saveServer")
                        .tint(.brandPrimary)
                        .disabled(viewModel.baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty || viewModel.isValidating)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}

@MainActor
private struct SeerrAuthMethodStepView: View {
    @Bindable var viewModel: SeerrViewModel
    var onSelectLocal: () -> Void
    var onSelectJellyfin: () -> Void

    var body: some View {
        SettingsScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SeerrCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Button {
                            Task {
                                await viewModel.signInWithPlex()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isAuthenticating {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("integrations.seerr.login.plex")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .settingsFocus("plexLogin", isDefault: true)
                        .tint(.brandPrimary)
                        .disabled(!viewModel.isPlexAuthAvailable || viewModel.isAuthenticating)

                        Text("integrations.seerr.login.plex.connectedAccount")
                            .foregroundStyle(.secondary)
                            .font(.callout)

                        if !viewModel.isPlexAuthAvailable {
                            Text("integrations.seerr.login.plex.unavailable")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }

                        if viewModel.isJellyfinAuthAvailable {
                            Divider().padding(.vertical, 4)

                            Button(action: onSelectJellyfin) {
                                Text("integrations.seerr.login.jellyfin")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .settingsFocus("jellyfinMethod", isDefault: !viewModel.isPlexAuthAvailable)
                            .disabled(viewModel.isAuthenticating)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        Button {
                            onSelectLocal()
                        } label: {
                            Text("integrations.seerr.login.local")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .settingsFocus(
                            "localMethod",
                            isDefault: !viewModel.isPlexAuthAvailable && !viewModel.isJellyfinAuthAvailable,
                        )
                        .disabled(viewModel.isAuthenticating)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}

@MainActor
private struct SeerrJellyfinAuthStepView: View {
    @Bindable var viewModel: SeerrViewModel

    var body: some View {
        SettingsScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SeerrCard {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("integrations.seerr.login.username", text: $viewModel.jellyfinUsername)
                            .settingsFocus("input", isDefault: true)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        SecureField("integrations.seerr.login.password", text: $viewModel.jellyfinPassword)
                            .settingsFocus("password")
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button {
                            Task { await viewModel.signInWithJellyfin() }
                        } label: {
                            Text("integrations.seerr.login.jellyfin")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .settingsFocus("jellyfinLogin")
                        .tint(.brandPrimary)
                        .disabled(
                            viewModel.jellyfinUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || viewModel.jellyfinPassword.isEmpty
                                || viewModel.isAuthenticating,
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}

@MainActor
private struct SeerrLocalAuthStepView: View {
    @Bindable var viewModel: SeerrViewModel

    var body: some View {
        SettingsScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SeerrCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("integrations.seerr.login.email")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        TextField("integrations.seerr.login.email", text: $viewModel.email)
                            .settingsFocus("input", isDefault: true)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Text("integrations.seerr.login.password")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        SecureField("integrations.seerr.login.password", text: $viewModel.password)
                            .settingsFocus("password")
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            Task {
                                await viewModel.signInWithLocal()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isAuthenticating {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("integrations.seerr.login.local")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .settingsFocus("localLogin")
                        .tint(.brandPrimary)
                        .disabled(viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty || viewModel.password.isEmpty || viewModel.isAuthenticating)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}

private struct SeerrSettingsErrorPresentation: ViewModifier {
    @Bindable var viewModel: SeerrViewModel
    @Environment(\.settingsFocusContext) private var focusContext

    func body(content: Content) -> some View {
        content.alert(
            "integrations.seerr.error.title",
            isPresented: Binding(
                get: { focusContext?.active == true && viewModel.isShowingError },
                set: { viewModel.isShowingError = $0 },
            ),
        ) {
            Button("common.actions.done") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}
