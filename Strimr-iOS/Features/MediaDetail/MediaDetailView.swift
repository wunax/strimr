import Observation
import SwiftUI

struct MediaDetailView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State var viewModel: MediaDetailViewModel
    @State private var isSummaryExpanded = false
    private let heroHeight: CGFloat = 320
    private let onPlay: (String, PlexItemType) -> Void
    private let onPlayFromStart: (String, PlexItemType) -> Void
    private let onShuffle: (String, PlexItemType) -> Void
    private let onSelectMedia: (MediaDisplayItem) -> Void
    private let onSelectParentSeries: (PlayableMediaItem) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onPlayFromStart: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onShuffle: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onSelectParentSeries: @escaping (PlayableMediaItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onPlayFromStart = onPlayFromStart
        self.onShuffle = onShuffle
        self.onSelectMedia = onSelectMedia
        self.onSelectParentSeries = onSelectParentSeries
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
                    onPlayFromStart: onPlayFromStart,
                    onShuffle: onShuffle,
                    onSelectParentSeries: {
                        guard let parentSeries = bindableViewModel.parentSeries else { return }
                        onSelectParentSeries(parentSeries)
                    },
                )

                if [.show, .season].contains(bindableViewModel.media.type) {
                    SeasonEpisodesSection(
                        viewModel: bindableViewModel,
                        onSelectSeason: { onSelectMedia(.playable($0)) },
                        onSelectEpisode: { onSelectMedia(.playable($0)) },
                    )
                }

                CastSection(viewModel: bindableViewModel)

                RelatedHubsSection(
                    viewModel: bindableViewModel,
                    onSelectMedia: onSelectMedia,
                )
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await bindableViewModel.loadDetails()
        }
        .onAppear {
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onChange(of: coordinator.isPresentingPlayer) { _, isPresenting in
            guard !isPresenting else { return }
            Task { await bindableViewModel.loadDetails() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .background(gradientBackground(for: bindableViewModel))
    }

    private func gradientBackground(for viewModel: MediaDetailViewModel) -> some View {
        MediaBackdropGradient(colors: viewModel.backdropGradient)
            .ignoresSafeArea()
    }
}
