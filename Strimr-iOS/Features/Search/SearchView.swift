import SwiftUI

@MainActor
struct SearchView: View {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("tabs.search")
        .navigationBarTitleDisplayMode(.inline)
        .userMenuToolbar()
        .searchable(
            text: $bindableViewModel.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "search.prompt",
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
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.filteredItems) { media in
                    card(for: media)
                }
            }
        }
    }

    @ViewBuilder
    private func card(for media: MediaDisplayItem) -> some View {
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
            .padding(.horizontal, 2)
        }
    }
}
