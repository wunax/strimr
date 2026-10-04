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
        .sheet(isPresented: $viewModel.isShowingCustomAddress) {
            CustomServerAddressView(viewModel: viewModel)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("serverSelection.title")
                .font(.largeTitle.bold())
            Text("serverSelection.multiple.subtitle")
                .foregroundStyle(.secondary)
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
                    .font(.headline)
                Text("serverSelection.empty.description")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Text("serverSelection.retry")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.brandPrimary)
                        .foregroundStyle(.brandPrimaryForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
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
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.large)
            .tint(.brandPrimary)
            .disabled(viewModel.selectedServerIDs.isEmpty)
        }
    }

    private func serverRow(_ server: PlexCloudResource) -> some View {
        Button {
            viewModel.toggle(server)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(.brandPrimary.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "server.rack")
                            .foregroundStyle(.brandPrimary),
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    ServerConnectionSummary(server: server)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: viewModel.isSelected(server) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(viewModel.isSelected(server) ? Color.brandPrimary : Color.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("serverSelection.customAddress.use") {
                viewModel.showCustomAddress(for: server)
            }
        }
    }
}
