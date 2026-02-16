import SwiftUI

struct SeerrManageRequestsVisionView: View {
    @State var viewModel: SeerrManageRequestsViewModel

    init(viewModel: SeerrManageRequestsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            ForEach(viewModel.pendingRequests, id: \.id) { request in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.displayName(for: request))
                            .font(.headline)
                        if let requestedAt = viewModel.requestedAtText(for: request) {
                            Text(requestedAt)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if viewModel.is4kRequest(request) {
                            Text("seerr.manageRequests.badge.4k")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2), in: Capsule())
                        }
                    }

                    Spacer()

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
                .padding(.vertical, 4)
            }
        }
        .overlay {
            if viewModel.pendingRequests.isEmpty {
                ContentUnavailableView(
                    "seerr.manageRequests.empty",
                    systemImage: "checkmark.circle.fill",
                )
            }
        }
        .navigationTitle(viewModel.media.title ?? viewModel.media.name ?? "")
    }
}
