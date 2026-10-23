import SwiftUI

struct SelectServerView: View {
    @State private var viewModel: ServerSelectionViewModel

    init(viewModel: ServerSelectionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            header
            content
        }
        .padding(24)
        .task {
            await viewModel.load()
        }
        .sheet(item: $viewModel.customAddressModel) { model in
            CustomServerAddressView(model: model)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("serverSelection.title")
                .font(.heroTitle)
                .foregroundStyle(.textPrimary)
            Text("serverSelection.multiple.subtitle")
                .font(.bodyText)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.servers.isEmpty {
            ProgressView("serverSelection.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if viewModel.servers.isEmpty {
            VStack(spacing: 12) {
                Text("serverSelection.empty.title")
                    .font(.sectionTitle)
                    .foregroundStyle(.textPrimary)
                Text("serverSelection.empty.description")
                    .font(.bodyText)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Text("serverSelection.retry")
                        .frame(maxWidth: .infinity)
                }
                .actionButtonStyle(.primary)
                .disabled(viewModel.isLoading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.servers, id: \.clientIdentifier) { server in
                        serverRow(server)
                    }
                }
                .padding(.vertical, 8)
            }

            Button {
                viewModel.continueWithSelection()
            } label: {
                Text("common.actions.continue")
                    .frame(maxWidth: .infinity)
            }
            .actionButtonStyle(.primary)
            .disabled(viewModel.selectedServerIDs.isEmpty)
        }
    }

    private func serverRow(_ server: PlexCloudResource) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            serverToggle(server)
            if viewModel.suggestsCustomAddress(for: server) {
                Button("serverSelection.customAddress.suggest") {
                    viewModel.showCustomAddress(for: server)
                }
                .font(.facts.weight(.semibold))
                .tint(.textSecondary)
            }
        }
    }

    private func serverToggle(_ server: PlexCloudResource) -> some View {
        Button {
            viewModel.toggle(server)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(.surfaceRaised)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "server.rack")
                            .foregroundStyle(.textSecondary),
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.rowTitle)
                        .foregroundStyle(.textPrimary)
                    ServerConnectionSummary(state: viewModel.probeState(of: server))
                        .font(.facts)
                }

                Spacer()

                Image(systemName: viewModel.isSelected(server) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(viewModel.isSelected(server) ? Color.selectionAccent : Color.textTertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .surfaceSubtle,
                in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous),
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("serverSelection.customAddress.use") {
                viewModel.showCustomAddress(for: server)
            }
        }
    }
}
