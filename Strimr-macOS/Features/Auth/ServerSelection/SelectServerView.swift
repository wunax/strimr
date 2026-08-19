import SwiftUI

struct SelectServerView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var viewModel: ServerSelectionViewModel
    @State private var isShowingLogoutConfirmation = false

    init(viewModel: ServerSelectionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("serverSelection.title").font(.largeTitle.bold())
                    Text("serverSelection.subtitle").foregroundStyle(.secondary)
                }
                Spacer()
                AuthenticationActionsMenu(onSignOut: {
                    isShowingLogoutConfirmation = true
                })
            }

            if viewModel.isLoading, viewModel.servers.isEmpty {
                ProgressView("serverSelection.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.servers.isEmpty {
                ContentUnavailableView {
                    Label("serverSelection.empty.title", systemImage: "server.rack")
                } description: {
                    Text("serverSelection.empty.description")
                } actions: {
                    Button("serverSelection.retry") {
                        Task { await viewModel.load() }
                    }
                }
            } else {
                List(viewModel.servers, id: \.clientIdentifier) { server in
                    Button {
                        Task { await viewModel.select(server: server) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "server.rack")
                                .font(.title2)
                                .foregroundStyle(.brandPrimary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name).font(.headline)
                                Group {
                                    if viewModel.selectingServerID == server.clientIdentifier {
                                        Text(sessionManager.loadingPhase.title)
                                    } else {
                                        Text(connectionDescription(for: server))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectingServerID == server.clientIdentifier {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSelecting)
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(32)
        .task { await viewModel.load() }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .alert("serverSelection.error.connection.title", isPresented: $viewModel.isShowingSelectionError) {
            Button("common.actions.retry") { viewModel.requestSelectionRetry() }
            Button("common.actions.cancel", role: .cancel) { viewModel.dismissSelectionError() }
        } message: {
            Text("serverSelection.error.connection.message")
        }
        .onChange(of: viewModel.isShowingSelectionError) { _, isPresented in
            guard !isPresented else { return }
            Task { await viewModel.retrySelectionAfterAlertDismissal() }
        }
    }

    private func connectionDescription(for server: PlexCloudResource) -> String {
        guard let connection = server.connections?.first else {
            return String(localized: "serverSelection.connection.unavailable")
        }
        if connection.isLocal {
            return String(localized: "serverSelection.connection.localFormat \(connection.address)")
        }
        if connection.isRelay {
            return String(localized: "serverSelection.connection.relay")
        }
        return connection.address
    }
}
