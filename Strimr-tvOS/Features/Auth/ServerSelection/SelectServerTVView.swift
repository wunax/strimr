import SwiftUI

struct SelectServerTVView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State var viewModel: ServerSelectionViewModel
    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                header
                content
                Spacer()
            }
            .padding(48)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
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
        .task { await viewModel.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("serverSelection.title")
                .font(.largeTitle.bold())
            Text("serverSelection.subtitle")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.servers.isEmpty {
            ProgressView("serverSelection.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if viewModel.servers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("serverSelection.empty.title")
                    .font(.title2.bold())
                Text("serverSelection.empty.description")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Button {
                    Task { await viewModel.load() }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView().tint(.white)
                        }
                        Text("serverSelection.retry")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: 320)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .disabled(viewModel.isLoading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                LazyVStack(spacing: 64) {
                    ForEach(viewModel.servers, id: \.clientIdentifier) { server in
                        serverRow(server)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 60)
            }
        }
    }

    private func serverRow(_ server: PlexCloudResource) -> some View {
        Button {
            Task { await viewModel.select(server: server) }
        } label: {
            HStack(spacing: 48) {
                Circle()
                    .fill(.brandPrimary.opacity(0.2))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "server.rack")
                            .font(.title)
                            .foregroundStyle(.brandPrimary),
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(server.name)
                        .font(.title2.weight(.semibold))
                    connectionSummary(for: server)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func connectionSummary(for server: PlexCloudResource) -> some View {
        guard let connection = server.connections.first else {
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
