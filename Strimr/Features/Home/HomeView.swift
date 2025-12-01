import SwiftUI

@MainActor
struct HomeView: View {
    @State var viewModel: HomeViewModel
    let onSelectMedia: (MediaItem) -> Void

    init(
        viewModel: HomeViewModel,
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let hub = viewModel.continueWatching, hub.hasItems {
                    MediaHubSection(title: hub.title) {
                        MediaCarousel(
                            items: hub.items,
                            cardWidthFraction: 1/2,
                            spacing: 16
                        ) { media, width in
                            LandscapeMediaCard(media: media) {
                                onSelectMedia(media)
                            }
                            .frame(width: width)
                        }
                    }
                }

                if !viewModel.recentlyAdded.isEmpty {
                    ForEach(viewModel.recentlyAdded) { hub in
                        if hub.hasItems {
                            MediaHubSection(title: hub.title) {
                                MediaCarousel(
                                    items: hub.items,
                                    cardWidthFraction: 1/3,
                                    spacing: 12
                                ) { media, width in
                                    PortraitMediaCard(media: media) {
                                        onSelectMedia(media)
                                    }
                                    .frame(width: width)
                                }
                            }
                        }
                    }
                }

                if viewModel.isLoading && !viewModel.hasContent {
                    ProgressView("Loading home")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent && !viewModel.isLoading {
                    Text("Nothing to show yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle("Home")
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.reload()
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(plexApiManager: PlexAPIManager())
        )
    }
}
