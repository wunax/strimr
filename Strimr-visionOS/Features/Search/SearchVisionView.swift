import SwiftUI

@MainActor
struct SearchVisionView: View {
    @State var viewModel: SearchViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: SearchViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
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
            .padding(.horizontal, 24)
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
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 32) {
                ForEach(viewModel.filteredItems) { media in
                    SearchResultCard(media: media) {
                        onSelectMedia(media)
                    }
                }
            }
        }
    }

    private func filterPills() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.brandPrimary.opacity(0.18) : Color.secondary.opacity(0.1)),
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(isSelected ? Color.brandPrimary : Color.secondary.opacity(0.2), lineWidth: 1)
                        }
                        .foregroundStyle(isSelected ? Color.brandPrimary : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 200), spacing: 24),
            GridItem(.flexible(minimum: 200), spacing: 24),
            GridItem(.flexible(minimum: 200), spacing: 24),
        ]
    }
}
