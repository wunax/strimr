import SwiftUI

struct SelectServerVisionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State var viewModel: ServerSelectionViewModel
    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        VStack(spacing: 32) {
            header
            content
        }
        .padding(40)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isShowingLogoutConfirmation = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityLabel("common.actions.logOut")
            }
        }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("serverSelection.title")
                .font(.extraLargeTitle)
            Text("serverSelection.subtitle")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .font(.title3)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.servers.isEmpty {
            ProgressView("serverSelection.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if viewModel.servers.isEmpty {
            VStack(spacing: 16) {
                Text("serverSelection.empty.title")
                    .font(.headline)
                Text("serverSelection.empty.description")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await viewModel.load() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                        }
                        Text("serverSelection.retry")
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.servers, id: \.clientIdentifier) { server in
                        serverRow(server)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: 600)
        }
    }

    private func serverRow(_ server: PlexCloudResource) -> some View {
        Button {
            Task {
                await viewModel.select(server: server)
            }
        } label: {
            HStack(spacing: 16) {
                Circle()
                    .fill(.brandPrimary.opacity(0.2))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "server.rack")
                            .font(.title3)
                            .foregroundStyle(.brandPrimary),
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                    connectionSummary(for: server)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.selectingServerID == server.clientIdentifier {
                    ProgressView()
                        .tint(.brandPrimary)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(
                viewModel.isSelecting && viewModel.selectingServerID != server.clientIdentifier
                    ? 0.6
                    : 1,
            )
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .disabled(viewModel.isSelecting)
    }

    private func connectionSummary(for server: PlexCloudResource) -> some View {
        guard let connection = server.connections?.first else {
            return Text("serverSelection.connection.unavailable")
        }
        if connection.isLocal {
            return Text("serverSelection.connection.localFormat \(connection.address)")
        }
        if connection.isRelay {
            return Text("serverSelection.connection.relay")
        }
        return Text(connection.address)
    }
}
