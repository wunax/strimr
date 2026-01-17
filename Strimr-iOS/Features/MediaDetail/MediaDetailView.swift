import Observation
import SwiftUI

struct MediaDetailView: View {
    @Environment(MainCoordinator.self) private var coordinator
    @Environment(SettingsManager.self) private var settingsManager
    @State var viewModel: MediaDetailViewModel
    @State private var isSummaryExpanded = false
    private let heroHeight: CGFloat = 320
    private let onPlay: (String, String?) -> Void
    private let onPlayFromStart: (String, String?) -> Void
    private let onSelectMedia: (MediaItem) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String, String?) -> Void = { _, _ in },
        onPlayFromStart: @escaping (String, String?) -> Void = { _, _ in },
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in },
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
                    onPlay: { ratingKey in
                        Task {
                            let downloadPath = await viewModel.playbackDownloadPath(for: ratingKey)
                            onPlay(ratingKey, downloadPath)
                        }
                    },
                    onPlayFromStart: { ratingKey in
                        Task {
                            let downloadPath = await viewModel.playbackDownloadPath(for: ratingKey)
                            onPlayFromStart(ratingKey, downloadPath)
                        }
                    },
                    onDownloadClick: {
                    let type = viewModel.media.type
                    let settings = settingsManager.download
                    let shouldShow: Bool
                    switch type {
                    case .movie:
                        shouldShow = settings.showDownloadsAfterMovieDownload
                    case .show, .season:
                        shouldShow = settings.showDownloadsAfterShowDownload
                    case .episode:
                        shouldShow = settings.showDownloadsAfterEpisodeDownload
                    case .unknown:
                        shouldShow = true
                    }
                    
                    if type == .show {
                        coordinator.showSeriesDownloadSelection(for: viewModel.media)
                    } else if shouldShow || viewModel.downloadState == .downloaded {
                        coordinator.showDownloads()
                    }
                }
                )

                if bindableViewModel.media.type == .show {
                    SeasonEpisodesSection(
                        viewModel: bindableViewModel,
                        onPlay: { ratingKey in
                            Task {
                                let downloadPath = await viewModel.playbackDownloadPath(for: ratingKey)
                                onPlay(ratingKey, downloadPath)
                            }
                        },
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
