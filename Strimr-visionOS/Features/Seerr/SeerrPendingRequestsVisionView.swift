import SwiftUI

struct SeerrPendingRequestsVisionView: View {
    @State var viewModel: SeerrPendingRequestsViewModel

    init(viewModel: SeerrPendingRequestsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            ForEach(viewModel.requests, id: \.id) { request in
                let media = viewModel.mediaDetail(for: request)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.mediaTitle(for: media))
                            .font(.headline)
                        Text(viewModel.displayName(for: request))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let requestedAt = viewModel.requestedAtText(for: request) {
                            Text(requestedAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if viewModel.canManageRequests {
                        HStack(spacing: 8) {
                            Button {
                                Task { await viewModel.approve(request) }
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(viewModel.isUpdating(request))

                            Button {
                                Task { await viewModel.decline(request) }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(viewModel.isUpdating(request))
                        }
                    }
                }
                .padding(.vertical, 4)
                .onAppear {
                    Task { await viewModel.loadMoreIfNeeded(current: request) }
                }
            }
        }
        .overlay {
            if viewModel.isLoading, viewModel.requests.isEmpty {
                ProgressView()
            } else if viewModel.requests.isEmpty {
                ContentUnavailableView(
                    "seerr.manageRequests.empty",
                    systemImage: "checkmark.circle.fill",
                )
            }
        }
        .task {
            await viewModel.load()
        }
        .navigationTitle("seerr.requests.pending")
    }
}
