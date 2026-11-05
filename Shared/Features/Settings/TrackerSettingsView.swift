import SwiftUI
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

@MainActor
struct TrackerSettingsView: View {
    @Environment(LibraryStore.self) private var libraryStore

    let service: TrackerService
    @State private var connection: TrackerConnectionViewModel
    @State private var isCodeCopied = false

    private let coordinator = TrackerCoordinator.shared

    init(service: TrackerService) {
        self.service = service
        _connection = State(initialValue: TrackerConnectionViewModel(
            service: service,
            coordinator: TrackerCoordinator.shared,
        ))
    }

    private var state: TrackerAccountState {
        coordinator.state(for: service)
    }

    var body: some View {
        content
            .onDisappear { connection.cancel() }
    }

    private var content: some View {
        #if os(tvOS)
            SettingsList { sections }
        #else
            List { sections }
                .insetListStyle()
                .navigationTitle(service.displayName)
        #endif
    }

    @ViewBuilder
    private var sections: some View {
        if state.isConnected {
            accountSection
            librariesSection
        } else {
            connectSection
        }
    }

    // MARK: - Connecting

    private var connectSection: some View {
        Section {
            Text("integrations.trackers.description \(service.displayName)")
                .foregroundStyle(.secondary)

            if state.settings.needsReconnect {
                Label("integrations.trackers.reconnectNeeded", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            connectionContent

            websiteLink
        } footer: {
            Text("integrations.trackers.footer \(service.displayName)")
        }
    }

    @ViewBuilder
    private var connectionContent: some View {
        switch connection.state {
        case .idle, .connected:
            connectButton("integrations.trackers.connect")
        case .requestingCode, .finishing:
            ProgressView()
        case let .waiting(code):
            codeView(code)
            Button("common.actions.cancel", role: .cancel) {
                connection.cancel()
            }
            .trackerFocus("\(service.rawValue).cancel", isDefault: true)
        case let .failed(message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.red)
            connectButton("integrations.trackers.connect.retry")
        }
    }

    private func connectButton(_ title: LocalizedStringKey) -> some View {
        Button(title) {
            connection.start()
        }
        .trackerFocus("\(service.rawValue).connect", isDefault: true)
    }

    private func codeView(_ code: TrackerDeviceCode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("integrations.trackers.connect.instructions")
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 24) {
                if let image = QRCodeImage.make(code.scanURL.absoluteString) {
                    image
                        .resizable()
                        .interpolation(.none)
                        .frame(width: Self.qrCodeSize, height: Self.qrCodeSize)
                        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(code.userCode)
                        .font(.heroTitle)
                        .monospaced()
                    Text(code.verificationURL.absoluteString)
                        .font(.facts)
                        .foregroundStyle(.secondary)
                    #if !os(tvOS)
                        // Without a borderless style, a list row fires all of its buttons on any tap.
                        HStack(spacing: 16) {
                            Link("integrations.trackers.connect.open", destination: code.scanURL)
                            copyButton(code)
                        }
                        .buttonStyle(.borderless)
                    #endif
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("integrations.trackers.connect.waiting")
                            .font(.facts)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    #if !os(tvOS)
        private func copyButton(_ code: TrackerDeviceCode) -> some View {
            Button {
                Self.copyToPasteboard(code.userCode)
                isCodeCopied = true
            } label: {
                if isCodeCopied {
                    Label("integrations.trackers.connect.copied", systemImage: "checkmark")
                } else {
                    Label("integrations.trackers.connect.copy", systemImage: "doc.on.doc")
                }
            }
            .task(id: isCodeCopied) {
                guard isCodeCopied else { return }
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled {
                    isCodeCopied = false
                }
            }
        }

        private static func copyToPasteboard(_ text: String) {
            #if os(iOS)
                UIPasteboard.general.string = text
            #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            #endif
        }
    #endif

    private static var qrCodeSize: CGFloat {
        #if os(tvOS)
            260
        #else
            140
        #endif
    }

    @ViewBuilder
    private var websiteLink: some View {
        #if !os(tvOS)
            Link(service.displayName, destination: service.websiteURL)
                .foregroundStyle(.secondary)
        #endif
    }

    // MARK: - Connected

    private var accountSection: some View {
        Section {
            if let username = state.settings.username {
                Text("integrations.trackers.connectedAs \(username)")
            } else {
                Text("integrations.trackers.connected")
            }

            if let issue = state.issue {
                Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Toggle("integrations.trackers.sync", isOn: Binding(
                get: { state.settings.isEnabled },
                set: { coordinator.setEnabled($0, for: service) },
            ))
            .trackerFocus("\(service.rawValue).sync", isDefault: true)

            websiteLink

            Button("integrations.trackers.disconnect", role: .destructive) {
                Task { await coordinator.disconnect(service) }
            }
            .trackerFocus("\(service.rawValue).disconnect")
        } footer: {
            Text("integrations.trackers.footer \(service.displayName)")
        }
    }

    private var librariesSection: some View {
        Section {
            ForEach(libraryStore.libraries, id: \.identity) { library in
                Toggle(isOn: libraryBinding(library)) {
                    LibrarySettingsLabel(
                        title: library.title,
                        subtitle: libraryStore.showsServerNames ? libraryStore.serverName(for: library) : nil,
                    )
                }
                .trackerFocus("\(service.rawValue).library.\(library.identity.stableKey)")
            }
        } header: {
            Text("integrations.trackers.libraries")
        } footer: {
            Text("integrations.trackers.libraries.footer \(service.displayName)")
        }
        .task {
            try? await libraryStore.loadLibraries()
        }
    }

    private func libraryBinding(_ library: Library) -> Binding<Bool> {
        let key = TrackerCoordinator.libraryKey(server: library.server, libraryID: library.id)
        return Binding(
            get: { !state.settings.excludedLibraries.contains(key) },
            set: { coordinator.setLibrary(key, isExcluded: !$0, for: service) },
        )
    }
}

extension TrackerAccountState {
    /// Short status for the integrations list.
    var statusText: String {
        if isConnected {
            if let username = settings.username {
                return username
            }
            return String(localized: "integrations.trackers.connected")
        }
        if settings.needsReconnect {
            return String(localized: "integrations.trackers.reconnectNeeded")
        }
        return String(localized: "integrations.trackers.notConnected")
    }
}

private extension TrackerIssue {
    var message: LocalizedStringKey {
        switch self {
        case .accountLimit: "integrations.trackers.issue.accountLimit"
        case .accountLocked: "integrations.trackers.issue.accountLocked"
        }
    }
}

private extension View {
    func trackerFocus(_ id: String, isDefault: Bool = false) -> some View {
        #if os(tvOS)
            settingsFocus(id, isDefault: isDefault)
        #else
            self
        #endif
    }
}
