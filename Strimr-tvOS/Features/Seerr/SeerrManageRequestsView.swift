import Observation
import SwiftUI

@MainActor
struct SeerrManageRequestsView: View {
    @Bindable var viewModel: SeerrManageRequestsViewModel
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if viewModel.pendingRequests.isEmpty {
                        Text("seerr.manageRequests.empty")
                            .foregroundStyle(.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(viewModel.pendingRequests, id: \.id) { request in
                            requestCard(for: request)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("seerr.manageRequests.title")
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
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.surfaceSubtle),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.strokeSubtle, lineWidth: 1),
        )
        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 8)
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
                    case .empty:
                        Color.surfaceSubtle
                    case .failure:
                        Color.surfaceSubtle
                    @unknown default:
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
                    .font(.title3.weight(.semibold))

                if let requestedAt = viewModel.requestedAtText(for: request) {
                    Text(requestedAt)
                        .font(.footnote)
                        .foregroundStyle(.textSecondary)
                }

                if viewModel.is4kRequest(request) {
                    Text("seerr.manageRequests.badge.4k")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2), in: Capsule())
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
                .foregroundStyle(.textSecondary)
        } else {
            HStack(spacing: 8) {
                ForEach(seasonNumbers, id: \.self) { seasonNumber in
                    Text(String(localized: "seerr.manageRequests.season.badge \(seasonNumber)"))
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassSurface()
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
            .controlSize(.large)
            .tint(.red)
            .disabled(viewModel.isUpdating(request))
        }
    }
}
