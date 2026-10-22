import SwiftUI

@MainActor
struct SeerrDiscoverView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State var viewModel: SeerrDiscoverViewModel
    @State var searchViewModel: SeerrSearchViewModel
    let onSelectMedia: (SeerrMedia) -> Void

    init(
        viewModel: SeerrDiscoverViewModel,
        searchViewModel: SeerrSearchViewModel,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        _searchViewModel = State(initialValue: searchViewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if searchViewModel.isSearchActive {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(searchViewModel.searchResults, id: \.id) { media in
                            SeerrSearchCard(media: media) {
                                onSelectMedia(media)
                            }
                        }
                    }
                } else {
                    requestsEntry

                    if !viewModel.trending.isEmpty {
                        SeerrMediaSection(title: "integrations.seerr.discover.trending") {
                            SeerrMediaCarousel(
                                items: viewModel.trending,
                                showsLabels: true,
                                onSelectMedia: onSelectMedia,
                            )
                        }
                    }

                    if !viewModel.popularMovies.isEmpty {
                        SeerrMediaSection(title: "integrations.seerr.discover.popularMovies") {
                            SeerrMediaCarousel(
                                items: viewModel.popularMovies,
                                showsLabels: true,
                                onSelectMedia: onSelectMedia,
                            )
                        }
                    }

                    if !viewModel.upcomingMovies.isEmpty {
                        SeerrMediaSection(title: "integrations.seerr.discover.upcomingMovies") {
                            SeerrMediaCarousel(
                                items: viewModel.upcomingMovies,
                                showsLabels: true,
                                onSelectMedia: onSelectMedia,
                            )
                        }
                    }

                    if !viewModel.popularTV.isEmpty {
                        SeerrMediaSection(title: "integrations.seerr.discover.popularTV") {
                            SeerrMediaCarousel(
                                items: viewModel.popularTV,
                                showsLabels: true,
                                onSelectMedia: onSelectMedia,
                            )
                        }
                    }

                    if !viewModel.upcomingTV.isEmpty {
                        SeerrMediaSection(title: "integrations.seerr.discover.upcomingTV") {
                            SeerrMediaCarousel(
                                items: viewModel.upcomingTV,
                                showsLabels: true,
                                onSelectMedia: onSelectMedia,
                            )
                        }
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("integrations.seerr.discover.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = activeErrorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading, !searchViewModel.isSearchActive {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.textSecondary)
                } else if searchViewModel.isSearchActive,
                          !searchViewModel.isSearching,
                          searchViewModel.searchResults.isEmpty
                {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle("tabs.discover")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
        .task(id: searchViewModel.searchQuery) {
            await searchViewModel.search()
        }
        .refreshable {
            if searchViewModel.isSearchActive {
                await searchViewModel.search()
            } else {
                await viewModel.reload()
            }
        }
        .searchable(
            text: $searchViewModel.searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("integrations.seerr.search.placeholder"),
        )
    }

    private var requestsEntry: some View {
        Button {
            coordinator.showSeerrRequests()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tray.full.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("seerr.requests.title")
                        .font(.headline)
                    if viewModel.requestsBadgeCount > 0 {
                        Text(String(localized: "seerr.requests.pendingCount \(viewModel.requestsBadgeCount)"))
                            .font(.caption)
                            .foregroundStyle(.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var activeErrorMessage: String? {
        if searchViewModel.isSearchActive {
            return searchViewModel.errorMessage
        }
        return viewModel.errorMessage
    }
}
