import Observation
import SwiftUI

@MainActor
struct SeerrPendingRequestsView: View {
    @State var viewModel: SeerrPendingRequestsViewModel

    var body: some View {
        List {
            if viewModel.isLoading, viewModel.requests.isEmpty {
                ProgressView("integrations.seerr.discover.loading")
                    .frame(maxWidth: .infinity)
            } else if viewModel.requests.isEmpty {
                Text("seerr.manageRequests.empty")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.requests, id: \.id) { request in
                    Section {
                        requestRow(for: request)
                    }
                    .onAppear {
                        Task {
                            await viewModel.loadMoreIfNeeded(current: request)
                        }
                    }
                }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("seerr.manageRequests.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.reload()
        }
        .alert("integrations.seerr.error.title", isPresented: $viewModel.isShowingError) {
            Button("common.actions.done") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func requestRow(for request: SeerrRequest) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let media = viewModel.mediaDetail(for: request) {
                SeerrMediaArtworkView(media: media, width: 80, height: 120)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 80, height: 120)
            }

            VStack(alignment: .leading, spacing: 6) {
                let media = viewModel.mediaDetail(for: request)
                Text(viewModel.mediaTitle(for: media))
                    .font(.headline)

                if let year = viewModel.mediaYear(for: media) {
                    Text(year)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.displayName(for: request))
                    .font(.subheadline.weight(.semibold))

                if let requestedAt = viewModel.requestedAtText(for: request) {
                    Text(requestedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let profileName = viewModel.profileName(for: request) {
                    Text(String(localized: "seerr.manageRequests.profile \(profileName)"))
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

                seasonBadges(for: request)
            }

            Spacer()

            VStack(spacing: 12) {
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
        let mediaType = viewModel.mediaDetail(for: request)?.mediaType ?? request.media?.mediaType
        if mediaType == .tv {
            let seasonNumbers = viewModel.seasonNumbers(for: request)
            if seasonNumbers.isEmpty {
                Text("seerr.manageRequests.seasons.all")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(seasonNumbers, id: \.self) { seasonNumber in
                        Text(String(localized: "seerr.manageRequests.season.badge \(seasonNumber)"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
        }
    }
}
