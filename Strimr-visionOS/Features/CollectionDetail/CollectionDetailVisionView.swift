import SwiftUI

struct CollectionDetailVisionView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @State var viewModel: CollectionDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onPlay: (String) -> Void
    let onShuffle: (String) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 200), spacing: 20),
    ]

    init(
        viewModel: CollectionDetailViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onPlay: @escaping (String) -> Void = { _ in },
        onShuffle: @escaping (String) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onPlay = onPlay
        self.onShuffle = onShuffle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                gridContent
            }
            .padding(24)
        }
        .overlay {
            if viewModel.isLoading, viewModel.items.isEmpty {
                ProgressView()
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.items.isEmpty, !viewModel.isLoading {
                ContentUnavailableView(
                    "common.empty.nothingToShow",
                    systemImage: "rectangle.stack.fill",
                )
            }
        }
        .task {
            await viewModel.load()
        }
        .navigationTitle(viewModel.collection.title)
    }

    private var headerSection: some View {
        HStack(spacing: 20) {
            if viewModel.collection.thumbPath != nil {
                MediaImageView(
                    viewModel: MediaImageViewModel(
                        context: plexApiContext,
                        artworkKind: .thumb,
                        media: viewModel.collectionDisplayItem,
                    ),
                )
                .frame(width: 160, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.collection.title)
                    .font(.largeTitle.bold())

                if let count = viewModel.collection.childCount {
                    Text("collection.detail.itemCount \(count)")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        onPlay(viewModel.collection.id)
                    } label: {
                        Label("common.actions.play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandSecondary)
                    .foregroundStyle(.brandSecondaryForeground)

                    Button {
                        onShuffle(viewModel.collection.id)
                    } label: {
                        Label("common.actions.shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var gridContent: some View {
        LazyVGrid(columns: gridColumns, spacing: 20) {
            ForEach(viewModel.items) { media in
                PortraitMediaCard(media: media, width: 180, showsLabels: true) {
                    onSelectMedia(media)
                }
            }
        }
    }
}
