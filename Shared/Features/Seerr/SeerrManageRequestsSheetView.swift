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
                        .foregroundStyle(.textSecondary)
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
            .insetListStyle()
            .navigationTitle("seerr.manageRequests.title")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.actions.done") {
                            dismiss()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
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
                    default:
                        Color.surfaceSubtle
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(.surfaceSubtle)
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.displayName(for: request))
                    .font(.cardTitle)
                    .foregroundStyle(.textPrimary)
                if let requestedAt = viewModel.requestedAtText(for: request) {
                    Text(requestedAt)
                        .font(.cardMetadata)
                        .foregroundStyle(.textSecondary)
                }
                if viewModel.is4kRequest(request) {
                    Text("seerr.manageRequests.badge.4k")
                        .font(.badge)
                        .foregroundStyle(.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.surfaceRaised, in: Capsule())
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
                .buttonStyle(.borderless)
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
                .buttonStyle(.borderless)
                .tint(.red)
                .disabled(viewModel.isUpdating(request))
            }
        }
    }

    @ViewBuilder
    private func seasonBadges(for request: SeerrRequest) -> some View {
        let seasonNumbers = viewModel.seasonNumbers(for: request)
        Label(
            seasonNumbers.isEmpty
                ? String(localized: "seerr.manageRequests.seasons.all")
                : SeerrSeasonSummary.text(for: seasonNumbers, totalSeasons: viewModel.media.numberOfSeasons),
            systemImage: "rectangle.stack",
        )
        .font(.facts)
        .foregroundStyle(.textSecondary)
    }
}
