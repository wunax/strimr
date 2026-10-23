import SwiftUI

@MainActor
struct SeerrDiscoverView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsManager.self) private var settingsManager
    @State var viewModel: SeerrDiscoverViewModel
    @State var searchViewModel: SeerrSearchViewModel
    let onSelectMedia: (SeerrMedia) -> Void
    let onShowRequests: () -> Void

    init(
        viewModel: SeerrDiscoverViewModel,
        searchViewModel: SeerrSearchViewModel,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in },
        onShowRequests: @escaping () -> Void = {},
    ) {
        _viewModel = State(initialValue: viewModel)
        _searchViewModel = State(initialValue: searchViewModel)
        self.onSelectMedia = onSelectMedia
        self.onShowRequests = onShowRequests
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

                    rail(String(localized: "integrations.seerr.discover.trending"), items: viewModel.trending)
                    rail(String(localized: "integrations.seerr.discover.popularMovies"), items: viewModel.popularMovies)
                    rail(
                        String(localized: "integrations.seerr.discover.upcomingMovies"),
                        items: viewModel.upcomingMovies,
                    )
                    rail(String(localized: "integrations.seerr.discover.popularTV"), items: viewModel.popularTV)
                    rail(String(localized: "integrations.seerr.discover.upcomingTV"), items: viewModel.upcomingTV)
                }

                if viewModel.isLoading, !viewModel.hasContent, !searchViewModel.isSearchActive {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(0 ..< 3, id: \.self) { _ in
                            SectionSkeleton(showsLabels: settingsManager.interface.showsCardLabels)
                        }
                    }
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
            .padding(.horizontal, LayoutMetrics.pageMargin)
            .padding(.vertical, 20)
        }
        .navigationTitle("tabs.discover")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
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
        #if os(iOS)
            .searchable(
                text: $searchViewModel.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("integrations.seerr.search.placeholder"),
            )
        #else
            .searchable(
                text: $searchViewModel.searchQuery,
                prompt: Text("integrations.seerr.search.placeholder"),
            )
        #endif
    }

    private var requestsEntry: some View {
        Button(action: onShowRequests) {
            HStack(spacing: 12) {
                Image(systemName: "tray.full.fill")
                    .font(.title3)
                    .foregroundStyle(.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("seerr.requests.title")
                        .font(.rowTitle)
                    if viewModel.requestsBadgeCount > 0 {
                        Text(String(localized: "seerr.requests.pendingCount \(viewModel.requestsBadgeCount)"))
                            .font(.cardMetadata)
                            .foregroundStyle(.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .glassSurface(in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rail(_ title: String, items: [SeerrMedia]) -> some View {
        if !items.isEmpty {
            MediaHubSection(title: title) {
                SeerrMediaCarousel(
                    items: items,
                    showsLabels: settingsManager.interface.showsCardLabels,
                    onSelectMedia: onSelectMedia,
                )
            }
        }
    }

    private var activeErrorMessage: String? {
        if searchViewModel.isSearchActive {
            return searchViewModel.errorMessage
        }
        return viewModel.errorMessage
    }
}
