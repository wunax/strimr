import SwiftUI

/// A server of the active profile: its activation, how it is reached and, for Plex, its custom address.
struct ServerDetailView: View {
    @Environment(SessionManager.self) private var sessionManager

    let server: ServerIdentity

    @State private var customAddress: URL?
    @State private var addressModel: CustomServerAddressModel?

    private var registry: ServerRegistry {
        sessionManager.registry
    }

    var body: some View {
        Group {
            if let session = registry.session(for: server) {
                form(for: session)
            } else {
                ContentUnavailableView("settings.server.missing", systemImage: "server.rack")
            }
        }
        .taskModalTitle(verbatim: registry.serverName(for: server) ?? "")
        .onAppear(perform: loadCustomAddress)
        .taskPresentation(item: $addressModel) { model in
            CustomServerAddressView(model: model)
        }
    }

    private func form(for session: ServerSession) -> some View {
        Form {
            Section {
                Toggle("settings.server.enabled", isOn: Binding(
                    get: { session.isEnabled },
                    set: { registry.setEnabled($0, server: server) },
                ))
                LabeledContent("settings.server.status") {
                    ServerStatusText(session: session, connectionKind: registry.plexConnectionKind(for: server))
                }
                if session.isEnabled, session.status == .ready, let kind = registry.plexConnectionKind(for: server) {
                    LabeledContent("settings.server.connection") {
                        Text(kind.title)
                    }
                }
            }

            if let resource = registry.plexResource(for: server) {
                Section {
                    Button { editCustomAddress(resource) } label: {
                        HStack {
                            Text("settings.server.customAddress")
                            Spacer()
                            Text(customAddress
                                .map(\.absoluteString) ?? String(localized: "settings.server.customAddress.none"))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("settings.server.customAddress.footer")
                }
            }
        }
    }

    private func loadCustomAddress() {
        guard let resource = registry.plexResource(for: server) else { return }
        customAddress = PlexAPIContext().customServerURL(for: resource)
    }

    private func editCustomAddress(_: PlexCloudResource) {
        addressModel = CustomServerAddressModel(
            address: customAddress,
            save: { url in try await registry.setCustomAddress(url, server: server) },
            remove: customAddress == nil ? nil : { try await registry.setCustomAddress(nil, server: server) },
            onDone: {
                addressModel = nil
                loadCustomAddress()
            },
        )
    }
}

/// Status of a server, with the relay and custom address hints of a Plex server.
struct ServerStatusText: View {
    let session: ServerSession
    let connectionKind: PlexConnectionKind?

    var body: some View {
        Text(title)
            .foregroundStyle(color)
    }

    private var title: LocalizedStringKey {
        guard session.isEnabled else { return "settings.accounts.status.disabled" }
        switch session.status {
        case .connecting:
            return "settings.accounts.status.connecting"
        case .ready:
            return connectionKind == .relay ? "settings.accounts.status.readyRelay" : "settings.accounts.status.ready"
        case .unreachable:
            return session.identity.provider == .plex
                ? "settings.accounts.status.unreachableSetAddress"
                : "settings.accounts.status.unreachable"
        case .needsReauthentication:
            return "settings.accounts.status.needsReauthentication"
        }
    }

    private var color: Color {
        guard session.isEnabled else { return .secondary }
        switch session.status {
        case .ready:
            return connectionKind == .relay ? .orange : .green
        case .connecting:
            return .secondary
        case .unreachable, .needsReauthentication:
            return .orange
        }
    }
}

extension PlexConnectionKind {
    var title: LocalizedStringKey {
        switch self {
        case .local:
            "settings.server.connection.local"
        case .remote:
            "settings.server.connection.remote"
        case .relay:
            "settings.server.connection.relay"
        case .custom:
            "settings.server.connection.custom"
        }
    }
}
