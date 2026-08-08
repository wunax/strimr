import SwiftUI

@MainActor
struct SearchTVView: View {
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
        .sheet(item: $selectedResult) { result in
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
            selectedResult = result
        }
    }

    private func filterPills() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 32) {
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
                                .fill(isSelected ? Color.brandPrimary.opacity(0.18) : Color.gray.opacity(0.12)),
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
