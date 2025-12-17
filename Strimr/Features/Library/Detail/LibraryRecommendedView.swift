import SwiftUI

struct LibraryRecommendedView: View {
    @State var viewModel: LibraryRecommendedViewModel
    let onSelectMedia: (MediaItem) -> Void

    private let landscapeHubIdentifiers: [String] = [
        "inprogress",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(viewModel.hubs) { hub in
                    if hub.hasItems {
                        MediaHubSection(title: hub.title) {
                            carousel(for: hub)
                        }
                    }
                }

                if viewModel.isLoading && !viewModel.hasContent {
                    ProgressView("library.recommended.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent && !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func carousel(for hub: Hub) -> some View {
        if shouldUseLandscape(for: hub) {
            MediaCarousel(
                layout: .landscape,
                items: hub.items,
                onSelectMedia: onSelectMedia
            )
        } else {
            MediaCarousel(
                layout: .portrait,
                items: hub.items,
                onSelectMedia: onSelectMedia
            )
        }
    }

    private func shouldUseLandscape(for hub: Hub) -> Bool {
        let identifier = hub.id.lowercased()
        return landscapeHubIdentifiers.contains { identifier.contains($0) }
    }
}

#Preview {
    let context = PlexAPIContext()
    let viewModel = LibraryRecommendedViewModel(
        library: Library(id: "1", title: "Movies", type: .movie, sectionId: 1),
        context: context
    )
    viewModel.hubs = [
        Hub(id: "continuewatching", title: "Continue Watching", items: []),
    ]

    return LibraryRecommendedView(
        viewModel: viewModel,
        onSelectMedia: { _ in }
    )
    .environment(context)
}
