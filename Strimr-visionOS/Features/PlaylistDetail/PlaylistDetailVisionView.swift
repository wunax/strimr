import SwiftUI

struct PlaylistDetailVisionView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @State var viewModel: PlaylistDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onPlay: (String) -> Void
    let onShuffle: (String) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 200), spacing: 20),
    ]

    init(
        viewModel: PlaylistDetailViewModel,
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
                    systemImage: "music.note.list",
                )
            }
        }
        .task {
            await viewModel.load()
        }
        .navigationTitle(viewModel.playlist.title)
    }

    private var headerSection: some View {
        HStack(spacing: 20) {
            if viewModel.playlist.compositePath != nil {
                MediaImageView(
                    viewModel: MediaImageViewModel(
                        context: plexApiContext,
                        artworkKind: .thumb,
                        media: viewModel.playlistDisplayItem,
                    ),
                )
                .frame(width: 160, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.playlist.title)
                    .font(.largeTitle.bold())

                if let count = viewModel.playlist.leafCount {
                    Text("playlist.detail.itemCount \(count)")
                        .foregroundStyle(.secondary)
                }

                if let summary = viewModel.playlist.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 12) {
                    Button {
                        onPlay(viewModel.playlist.id)
                    } label: {
                        Label("common.actions.play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandSecondary)
                    .foregroundStyle(.brandSecondaryForeground)

                    Button {
                        onShuffle(viewModel.playlist.id)
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
