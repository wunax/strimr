import Observation
import SwiftUI

@MainActor
struct SeerrManageRequestsView: View {
    @Bindable var viewModel: SeerrManageRequestsViewModel
    let onComplete: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if viewModel.pendingRequests.isEmpty {
                    Text("seerr.manageRequests.empty")
                        .font(.bodyText)
                        .foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(viewModel.pendingRequests, id: \.id) { request in
                        requestCard(for: request)
                    }
                }
            }
            .padding(24)
        }
        .taskModalTitle("seerr.manageRequests.title")
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

    private func requestCard(for request: SeerrRequest) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            requestHeader(for: request)

            if viewModel.isTV {
                seasonBadges(for: request)
            }

            requestActions(for: request)
        }
        .padding(24)
        .background(.surfaceSubtle, in: cardShape)
        .overlay(cardShape.stroke(.strokeSubtle, lineWidth: 1))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous)
    }

    private func requestHeader(for request: SeerrRequest) -> some View {
        HStack(alignment: .top, spacing: 16) {
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
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(.surfaceSubtle)
                    .frame(width: 56, height: 56)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.displayName(for: request))
                    .font(.sectionTitle)
                    .foregroundStyle(.textPrimary)

                if let requestedAt = viewModel.requestedAtText(for: request) {
                    Text(requestedAt)
                        .font(.facts)
                        .foregroundStyle(.textSecondary)
                }

                if viewModel.is4kRequest(request) {
                    Text("seerr.manageRequests.badge.4k")
                        .font(.badge)
                        .foregroundStyle(.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.surfaceRaised, in: Capsule())
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func seasonBadges(for request: SeerrRequest) -> some View {
        let seasonNumbers = viewModel.seasonNumbers(for: request)
        if seasonNumbers.isEmpty {
            Text("seerr.manageRequests.seasons.all")
                .font(.facts)
                .foregroundStyle(.textSecondary)
        } else {
            HStack(spacing: 8) {
                ForEach(seasonNumbers, id: \.self) { seasonNumber in
                    Text(String(localized: "seerr.manageRequests.season.badge \(seasonNumber)"))
                        .font(.badge)
                        .foregroundStyle(.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.surfaceRaised, in: Capsule())
                }
            }
        }
    }

    private func requestActions(for request: SeerrRequest) -> some View {
        HStack(spacing: 16) {
            Button {
                Task {
                    await viewModel.approve(request)
                }
            } label: {
                Label("seerr.manageRequests.action.accept", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.green)
            .disabled(viewModel.isUpdating(request))

            Button {
                Task {
                    await viewModel.decline(request)
                }
            } label: {
                Label("seerr.manageRequests.action.decline", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.red)
            .disabled(viewModel.isUpdating(request))
        }
    }
}
