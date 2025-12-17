import SwiftUI

@MainActor
struct SearchView: View {
    @State var viewModel: SearchViewModel
    let onSelectMedia: (MediaItem) -> Void

    init(
        viewModel: SearchViewModel,
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterPills()
                resultsContent()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("tabs.search")
        .searchable(
            text: $bindableViewModel.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "search.prompt"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onChange(of: bindableViewModel.query) { _, _ in
            viewModel.queryDidChange()
        }
        .onSubmit(of: .search) {
            viewModel.submitSearch()
        }
    }

    @ViewBuilder
    private func resultsContent() -> some View {
        if !viewModel.hasQuery {
            ContentUnavailableView("search.empty.title", systemImage: "magnifyingglass", description: Text("search.empty.description"))
                .frame(maxWidth: .infinity)
        } else if viewModel.isLoading {
            ProgressView("search.loading")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else if viewModel.filteredItems.isEmpty {
            ContentUnavailableView("search.noResults.title", systemImage: "film.stack.fill", description: Text("search.noResults.description"))
                .frame(maxWidth: .infinity)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.filteredItems) { media in
                    card(for: media)
                }
            }
        }
    }

    @ViewBuilder
    private func card(for media: MediaItem) -> some View {
        SearchResultCard(media: media) {
            onSelectMedia(media)
        }
    }

    private func filterPills() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases) { filter in
                    let isSelected = viewModel.activeFilters.contains(filter)
                    Button {
                        viewModel.toggleFilter(filter)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.systemImageName)
                                .font(.subheadline)
                            Text(filter.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.brandPrimary.opacity(0.18) : Color.gray.opacity(0.12))
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(isSelected ? Color.brandPrimary : Color.gray.opacity(0.25), lineWidth: 1)
                        }
                        .foregroundStyle(isSelected ? Color.brandPrimary : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

#Preview {
    let context = PlexAPIContext()
    let viewModel = SearchViewModel(context: context)
    viewModel.query = "Star"
    viewModel.items = [
        MediaItem(
            id: "movie1",
            summary: "A blockbuster space adventure.",
            title: "Star Quest",
            type: .movie,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: ["Sci-Fi"],
            year: 2024,
            duration: 7200,
            rating: 8.2,
            contentRating: "PG-13",
            studio: "Strimr Studios",
            tagline: "Explore the unknown.",
            thumbPath: nil,
            artPath: nil,
            ultraBlurColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil
        ),
        MediaItem(
            id: "show1",
            summary: "Life aboard a distant station.",
            title: "Orbital",
            type: .show,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: ["Drama"],
            year: 2023,
            duration: nil,
            rating: 7.9,
            contentRating: "TV-14",
            studio: "Strimr Originals",
            tagline: "Holding the line.",
            thumbPath: nil,
            artPath: nil,
            ultraBlurColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: 3,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil
        ),
        MediaItem(
            id: "episode1",
            summary: "The crew discovers a hidden signal.",
            title: "Episode 1",
            type: .episode,
            parentRatingKey: "season1",
            grandparentRatingKey: "show1",
            genres: ["Drama"],
            year: 2023,
            duration: 3600,
            rating: 8.1,
            contentRating: "TV-14",
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            ultraBlurColors: nil,
            viewOffset: 1200,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: "Orbital",
            parentTitle: "Season 1",
            parentIndex: 1,
            index: 1,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil
        ),
    ]

    return NavigationStack {
        SearchView(viewModel: viewModel)
    }
    .environment(context)
}
