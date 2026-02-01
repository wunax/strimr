import Observation
import SwiftUI

@MainActor
struct SeerrPendingRequestsTVView: View {
    @State var viewModel: SeerrPendingRequestsViewModel

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if viewModel.isLoading, viewModel.requests.isEmpty {
                        ProgressView("integrations.seerr.discover.loading")
                            .frame(maxWidth: .infinity)
                    } else if viewModel.requests.isEmpty {
                        Text("seerr.manageRequests.empty")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(viewModel.requests, id: \.id) { request in
                            requestCard(for: request)
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
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("seerr.manageRequests.title")
        .task {
            await viewModel.load()
        }
        .alert("integrations.seerr.error.title", isPresented: $viewModel.isShowingError) {
            Button("common.actions.done") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func requestCard(for request: SeerrRequest) -> some View {
        let media = viewModel.mediaDetail(for: request)

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                if let media {
                    SeerrMediaArtworkView(media: media, width: 160, height: 240)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 120, height: 180)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.mediaTitle(for: media))
                        .font(.title3.weight(.semibold))

                    if let year = viewModel.mediaYear(for: media) {
                        Text(year)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(viewModel.displayName(for: request))
                        .font(.headline)

                    if let requestedAt = viewModel.requestedAtText(for: request) {
                        Text(requestedAt)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let profileName = viewModel.profileName(for: request) {
                        Text(String(localized: "seerr.manageRequests.profile \(profileName)"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.is4kRequest(request) {
                        Text("seerr.manageRequests.badge.4k")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.2), in: Capsule())
                    }

                    seasonBadges(for: request)
                }

                Spacer()
            }

            requestActions(for: request)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 8)
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

    @ViewBuilder
    private func seasonBadges(for request: SeerrRequest) -> some View {
        let mediaType = viewModel.mediaDetail(for: request)?.mediaType ?? request.media?.mediaType
        if mediaType == .tv {
            let seasonNumbers = viewModel.seasonNumbers(for: request)
            if seasonNumbers.isEmpty {
                Text("seerr.manageRequests.seasons.all")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(seasonNumbers, id: \.self) { seasonNumber in
                        Text("S\(seasonNumber)")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
        }
    }
}
