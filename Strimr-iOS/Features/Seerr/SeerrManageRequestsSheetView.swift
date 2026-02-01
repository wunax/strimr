import Observation
import SwiftUI

@MainActor
struct SeerrManageRequestsSheetView: View {
    @Bindable var viewModel: SeerrManageRequestsViewModel
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.pendingRequests.isEmpty {
                    Text("seerr.manageRequests.empty")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.pendingRequests, id: \.id) { request in
                        Section {
                            requestHeader(for: request)

                            if viewModel.isTV {
                                seasonBadges(for: request)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("seerr.manageRequests.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.actions.done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("integrations.seerr.error.title", isPresented: $viewModel.isShowingError) {
            Button("common.actions.done") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.pendingRequests.isEmpty) { _, isEmpty in
            if isEmpty {
                onComplete()
            }
        }
        .onDisappear {
            onComplete()
        }
    }

    private func requestHeader(for request: SeerrRequest) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let avatarURL = viewModel.avatarURL(for: request.requestedBy) {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        Color.gray.opacity(0.2)
                    case .failure:
                        Color.gray.opacity(0.2)
                    @unknown default:
                        Color.gray.opacity(0.2)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.displayName(for: request))
                    .font(.headline)
                if let requestedAt = viewModel.requestedAtText(for: request) {
                    Text(requestedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.is4kRequest(request) {
                    Text("seerr.manageRequests.badge.4k")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2), in: Capsule())
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.approve(request)
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                }
                .tint(.green)
                .disabled(viewModel.isUpdating(request))

                Button {
                    Task {
                        await viewModel.decline(request)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .tint(.red)
                .disabled(viewModel.isUpdating(request))
            }
        }
    }

    @ViewBuilder
    private func seasonBadges(for request: SeerrRequest) -> some View {
        let seasonNumbers = viewModel.seasonNumbers(for: request)
        if seasonNumbers.isEmpty {
            Text("seerr.manageRequests.seasons.all")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                ForEach(seasonNumbers, id: \.self) { seasonNumber in
                    Text("S\(seasonNumber)")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }
}
