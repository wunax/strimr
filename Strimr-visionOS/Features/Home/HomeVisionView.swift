import SwiftUI

@MainActor
struct HomeVisionView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @State var viewModel: HomeViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: HomeViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let heroMedia {
                    heroSection(media: heroMedia)
                }

                if let hub = viewModel.continueWatching, hub.hasItems {
                    MediaHubSection(title: hub.title) {
                        MediaCarousel(
                            layout: .landscape,
                            items: hub.items,
                            showsLabels: false,
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }

                if !viewModel.recentlyAdded.isEmpty {
                    ForEach(viewModel.recentlyAdded) { hub in
                        if hub.hasItems {
                            MediaHubSection(title: hub.title) {
                                MediaCarousel(
                                    layout: .portrait,
                                    items: hub.items,
                                    showsLabels: false,
                                    onSelectMedia: onSelectMedia,
                                )
                            }
                        }
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("home.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .task {
            await viewModel.load()
        }
    }

    private func heroSection(media: MediaDisplayItem) -> some View {
        HStack(alignment: .top, spacing: 24) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    context: plexApiContext,
                    artworkKind: .art,
                    media: media,
                ),
            )
            .frame(width: 600, height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text(media.title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)

                if let secondaryLabel = media.secondaryLabel {
                    Text(secondaryLabel)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let summary = media.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 16)
    }

    private var heroMedia: MediaDisplayItem? {
        if let continueItem = viewModel.continueWatching?.items.first {
            return continueItem
        }

        for hub in viewModel.recentlyAdded where hub.hasItems {
            if let item = hub.items.first {
                return item
            }
        }

        return nil
    }
}
