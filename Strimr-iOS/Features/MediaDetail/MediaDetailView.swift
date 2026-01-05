import Observation
import SwiftUI

struct MediaDetailView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @State var viewModel: MediaDetailViewModel
    @State private var isSummaryExpanded = false
    private let heroHeight: CGFloat = 320
    private let onPlay: (String) -> Void
    private let onPlayFromStart: (String) -> Void
    private let onSelectMedia: (MediaItem) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String) -> Void = { _ in },
        onPlayFromStart: @escaping (String) -> Void = { _ in },
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onPlayFromStart = onPlayFromStart
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
                    onPlay: onPlay,
                    onPlayFromStart: onPlayFromStart
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
        .onChange(of: coordinator.isPresentingPlayer) { _, isPresenting in
            guard !isPresenting else { return }
            Task { await bindableViewModel.loadDetails() }
        }
        .background(gradientBackground(for: bindableViewModel))
    }

    private func gradientBackground(for viewModel: MediaDetailViewModel) -> some View {
        MediaBackdropGradient(colors: viewModel.backdropGradient)
            .ignoresSafeArea()
    }
}
