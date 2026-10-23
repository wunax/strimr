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
                .font(.heroTitle)
                .foregroundStyle(.textPrimary)
            Text("serverSelection.multiple.subtitle")
                .foregroundStyle(.textSecondary)
                .font(.bodyText)
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
                    .font(.sectionTitle)
                    .foregroundStyle(.textPrimary)
                Text("serverSelection.empty.description")
                    .foregroundStyle(.textSecondary)
                    .font(.bodyText)
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Text("serverSelection.retry")
                        .frame(maxWidth: 320)
                }
                .actionButtonStyle(.primary)
                .disabled(viewModel.isLoading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                LazyVStack(spacing: 40) {
                    ForEach(viewModel.servers, id: \.clientIdentifier) { server in
                        serverRow(server)
                    }

                    // Full-width focus section so focus can reach the centered button from the trailing custom address
                    // button.
                    HStack {
                        Button {
                            viewModel.continueWithSelection()
                        } label: {
                            Text("common.actions.continue")
                                .frame(maxWidth: 480)
                        }
                        .actionButtonStyle(.primary)
                        .disabled(viewModel.selectedServerIDs.isEmpty)
                    }
                    .frame(maxWidth: .infinity)
                    .focusSection()
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 60)
            }
        }
    }

    private func serverRow(_ server: PlexCloudResource) -> some View {
        VStack(alignment: .trailing, spacing: 32) {
            serverToggle(server)
            if viewModel.suggestsCustomAddress(for: server) {
                Button("serverSelection.customAddress.suggest") {
                    viewModel.showCustomAddress(for: server)
                }
                .font(.facts)
            }
        }
    }

    private func serverToggle(_ server: PlexCloudResource) -> some View {
        Button {
            viewModel.toggle(server)
        } label: {
            HStack(spacing: 48) {
                // Hierarchical styles: the focused plain button turns white.
                Circle()
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "server.rack")
                            .font(.title)
                            .foregroundStyle(.secondary),
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(server.name)
                        .font(.tileTitle)
                    ServerConnectionSummary(state: viewModel.probeState(of: server))
                        .font(.bodyText)
                }

                Spacer()

                Image(systemName: viewModel.isSelected(server) ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(viewModel.isSelected(server) ? Color.selectionAccent : Color.secondary)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .surfaceSubtle,
                in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous),
            )
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
