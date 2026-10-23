import SwiftUI

@MainActor
struct SearchView: View {
    @State var viewModel: SearchViewModel
    let onSelectMedia: (SearchResultSource) -> Void
    @State private var selectedResult: MergedSearchResult?

    init(
        viewModel: SearchViewModel,
        onSelectMedia: @escaping (SearchResultSource) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ZStack {
            Color("Background").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterPills()
                    resultsContent()
                    SearchUnavailableServersNote(names: viewModel.unavailableServerNames)
                }
            }
        }
        .searchable(text: $bindableViewModel.query, prompt: "search.prompt")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onChange(of: bindableViewModel.query) { _, _ in
            viewModel.queryDidChange()
        }
        .onSubmit(of: .search) {
            viewModel.submitSearch()
        }
        .taskPresentation(item: $selectedResult, style: .contextual) { result in
            SearchServerSelectionView(result: result, onSelect: onSelectMedia)
        }
    }

    @ViewBuilder
    private func resultsContent() -> some View {
        if !viewModel.hasQuery {
            ContentUnavailableView(
                "search.empty.title",
                systemImage: "magnifyingglass",
                description: Text("search.empty.description"),
            )
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
            ContentUnavailableView(
                "search.noResults.title",
                systemImage: "film.stack.fill",
                description: Text("search.noResults.description"),
            )
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 48) {
                ForEach(viewModel.filteredItems) { result in
                    card(for: result)
                }
            }
        }
    }

    private func card(for result: MergedSearchResult) -> some View {
        SearchResultCard(result: result) {
            select(result)
        }
    }

    private func select(_ result: MergedSearchResult) {
        if result.sources.count == 1 {
            onSelectMedia(result.primarySource)
        } else {
            selectedResult = result
        }
    }

    private func filterPills() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LayoutMetrics.chipSpacing) {
                ForEach(SearchFilter.allCases) { filter in
                    FilterChip(
                        title: filter.title,
                        systemImage: filter.systemImageName,
                        isSelected: viewModel.activeFilters.contains(filter),
                    ) {
                        viewModel.toggleFilter(filter)
                    }
                }
            }
            .padding(.vertical, 32)
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 320), spacing: 48),
            GridItem(.flexible(minimum: 320), spacing: 48),
        ]
    }
}
