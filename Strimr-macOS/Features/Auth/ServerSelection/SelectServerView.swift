import SwiftUI

struct SelectServerView: View {
    @State private var viewModel: ServerSelectionViewModel

    init(viewModel: ServerSelectionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("serverSelection.title")
                    .font(.heroTitle)
                    .foregroundStyle(.textPrimary)
                Text("serverSelection.multiple.subtitle")
                    .font(.bodyText)
                    .foregroundStyle(.textSecondary)
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
                    Toggle(isOn: Binding(
                        get: { viewModel.isSelected(server) },
                        set: { _ in viewModel.toggle(server) },
                    )) {
                        HStack(spacing: 14) {
                            Image(systemName: "server.rack")
                                .font(.title2)
                                .foregroundStyle(.textSecondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name)
                                    .font(.rowTitle)
                                    .foregroundStyle(.textPrimary)
                                ServerConnectionSummary(state: viewModel.probeState(of: server))
                                    .font(.cardMetadata)
                            }
                            if viewModel.suggestsCustomAddress(for: server) {
                                Spacer()
                                Button("serverSelection.customAddress.suggest") {
                                    viewModel.showCustomAddress(for: server)
                                }
                                .buttonStyle(.link)
                                .font(.cardMetadata)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.vertical, 5)
                    .contextMenu {
                        Button("serverSelection.customAddress.use") {
                            viewModel.showCustomAddress(for: server)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("common.actions.continue") {
                        viewModel.continueWithSelection()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.selectedServerIDs.isEmpty)
                }
            }
        }
        .padding(32)
        .task { await viewModel.load() }
        .sheet(item: $viewModel.customAddressModel) { model in
            CustomServerAddressView(model: model)
        }
    }
}
