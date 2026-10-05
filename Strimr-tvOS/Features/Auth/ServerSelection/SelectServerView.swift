import SwiftUI

struct SelectServerView: View {
    @State private var viewModel: ServerSelectionViewModel
    @FocusState private var focusedServerID: String?

    init(viewModel: ServerSelectionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

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
        .task { await viewModel.load() }
        .taskPresentation(item: $viewModel.customAddressModel) { model in
            CustomServerAddressView(model: model)
        }
        .onAppear {
            if focusedServerID == nil, let firstServer = viewModel.servers.first {
                focusedServerID = firstServer.clientIdentifier
            }
        }
        .onChange(of: viewModel.servers) { _, newValue in
            if focusedServerID == nil, let firstServer = newValue.first {
                focusedServerID = firstServer.clientIdentifier
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("serverSelection.title")
                .font(.largeTitle.bold())
            Text("serverSelection.multiple.subtitle")
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
                    Text("serverSelection.retry")
                        .fontWeight(.semibold)
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
                LazyVStack(spacing: 40) {
                    ForEach(viewModel.servers, id: \.clientIdentifier) { server in
                        serverRow(server)
                    }

                    Button {
                        viewModel.continueWithSelection()
                    } label: {
                        Text("common.actions.continue")
                            .fontWeight(.semibold)
                            .frame(maxWidth: 480)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .disabled(viewModel.selectedServerIDs.isEmpty)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 60)
            }
        }
    }

    private func serverRow(_ server: PlexCloudResource) -> some View {
        VStack(alignment: .trailing, spacing: 16) {
            serverToggle(server)
            if viewModel.suggestsCustomAddress(for: server) {
                Button("serverSelection.customAddress.suggest") {
                    viewModel.showCustomAddress(for: server)
                }
                .font(.callout)
            }
        }
    }

    private func serverToggle(_ server: PlexCloudResource) -> some View {
        Button {
            viewModel.toggle(server)
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
                    ServerConnectionSummary(state: viewModel.probeState(of: server))
                }

                Spacer()

                Image(systemName: viewModel.isSelected(server) ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(viewModel.isSelected(server) ? Color.brandPrimary : Color.secondary)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focusedServerID, equals: server.clientIdentifier)
        .contextMenu {
            Button("serverSelection.customAddress.use") {
                viewModel.showCustomAddress(for: server)
            }
        }
    }
}
