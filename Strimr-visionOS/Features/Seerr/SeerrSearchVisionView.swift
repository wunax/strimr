import SwiftUI

@MainActor
struct SeerrSearchVisionView: View {
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
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                spacing: 16,
            ) {
                ForEach(viewModel.searchResults) { media in
                    SeerrSearchCard(media: media) {
                        onSelectMedia(media)
                    }
                }
            }
            .padding(24)
        }
        .searchable(
            text: Binding(
                get: { viewModel.searchQuery },
                set: { viewModel.searchQuery = $0 }
            ),
            prompt: "seerr.search.prompt"
        )
        .autocorrectionDisabled()
        .onChange(of: viewModel.searchQuery) { _, _ in
            Task { await viewModel.search() }
        }
        .overlay {
            if viewModel.isSearching {
                ProgressView()
            } else if viewModel.searchResults.isEmpty, viewModel.isSearchActive {
                ContentUnavailableView(
                    "search.noResults.title",
                    systemImage: "magnifyingglass",
                )
            }
        }
    }
}
