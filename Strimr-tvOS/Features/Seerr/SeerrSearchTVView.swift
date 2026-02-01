import SwiftUI

@MainActor
struct SeerrSearchTVView: View {
    @State var viewModel: SeerrSearchViewModel
    let onSelectMedia: (SeerrMedia) -> Void

    init(
        viewModel: SeerrSearchViewModel,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in },
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
                    resultsContent
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .searchable(
            text: $bindableViewModel.searchQuery,
            prompt: Text("integrations.seerr.search.placeholder"),
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("tabs.search")
        .task(id: viewModel.searchQuery) {
            await viewModel.search()
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if !viewModel.isSearchActive {
            ContentUnavailableView(
                "tabs.search",
                systemImage: "magnifyingglass",
                description: Text("integrations.seerr.search.placeholder"),
            )
            .frame(maxWidth: .infinity)
        } else if viewModel.isSearching {
            ProgressView("integrations.seerr.discover.loading")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else if viewModel.searchResults.isEmpty {
            ContentUnavailableView(
                "common.empty.nothingToShow",
                systemImage: "film.stack.fill",
                description: Text("integrations.seerr.search.placeholder"),
            )
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 32) {
                ForEach(viewModel.searchResults) { media in
                    SeerrSearchCard(media: media) {
                        onSelectMedia(media)
                    }
                }
            }
            .focusSection()
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 320), spacing: 32),
            GridItem(.flexible(minimum: 320), spacing: 32),
        ]
    }
}
