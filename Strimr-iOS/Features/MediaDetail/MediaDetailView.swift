import Observation
import SwiftUI

struct MediaDetailView: View {
    @State var viewModel: MediaDetailViewModel
    @State private var isSummaryExpanded = false
    private let heroHeight: CGFloat = 320
    private let onPlay: (String) -> Void
    private let onSelectMedia: (MediaItem) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String) -> Void = { _ in },
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                MediaDetailHeaderSection(
                    viewModel: bindableViewModel,
                    isSummaryExpanded: $isSummaryExpanded,
                    heroHeight: heroHeight,
                    onPlay: onPlay
                )

                if bindableViewModel.media.type == .show {
                    SeasonEpisodesSection(
                        viewModel: bindableViewModel,
                        onPlay: onPlay
                    )
                }

                CastSection(viewModel: bindableViewModel)

                RelatedHubsSection(
                    viewModel: bindableViewModel,
                    onSelectMedia: onSelectMedia
                )
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await bindableViewModel.loadDetails()
        }
        .background(gradientBackground(for: bindableViewModel))
    }

    private func gradientBackground(for viewModel: MediaDetailViewModel) -> some View {
        MediaBackdropGradient(colors: viewModel.backdropGradient)
            .ignoresSafeArea()
    }
}

#Preview {
    let context = PlexAPIContext()
    let sample = MediaItem(
        id: "1",
        summary: "A high-stakes story about streaming.",
        title: "Strimr Origins",
        type: .movie,
        parentRatingKey: nil,
        grandparentRatingKey: nil,
        genres: ["Drama", "Tech"],
        year: 2024,
        duration: 7200,
        rating: 8.4,
        contentRating: "PG-13",
        studio: "Strimr Studios",
        tagline: "Stream smarter.",
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
    )

    return MediaDetailView(
        viewModel: MediaDetailViewModel(media: sample, context: context)
    )
    .environment(context)
}
