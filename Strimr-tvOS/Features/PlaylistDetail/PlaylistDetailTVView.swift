import Observation
import SwiftUI

struct PlaylistDetailTVView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @State var viewModel: PlaylistDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onPlay: (String) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 200, maximum: 200), spacing: 32),
    ]

    init(
        viewModel: PlaylistDetailViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onPlay: @escaping (String) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onPlay = onPlay
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                headerSection

                LazyVGrid(columns: gridColumns, spacing: 32) {
                    ForEach(bindableViewModel.items) { media in
                        PortraitMediaCard(media: media, width: 200, showsLabels: true) {
                            onSelectMedia(media)
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .overlay {
            if bindableViewModel.isLoading, bindableViewModel.items.isEmpty {
                ProgressView("library.browse.loading")
            } else if let errorMessage = bindableViewModel.errorMessage, bindableViewModel.items.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater"),
                )
                .symbolRenderingMode(.multicolor)
            } else if bindableViewModel.items.isEmpty {
                ContentUnavailableView(
                    "library.browse.empty.title",
                    systemImage: "square.grid.2x2.fill",
                    description: Text("library.browse.empty.description"),
                )
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task {
            await bindableViewModel.load()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 32) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    context: plexApiContext,
                    artworkKind: .thumb,
                    media: viewModel.playlistDisplayItem,
                ),
            )
            .frame(width: 280, height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.playlist.title)
                    .font(.title2)
                    .fontWeight(.bold)

                if let elementsCountText = viewModel.elementsCountText {
                    Text(elementsCountText)
                        .font(.headline)
                        .foregroundStyle(.brandSecondary)
                }

                if let durationText = viewModel.durationText {
                    Text(durationText)
                        .font(.headline)
                        .foregroundStyle(.brandSecondary)
                }

                if let summary = viewModel.playlist.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.headline)
                        .foregroundStyle(.brandSecondary)
                }

                playButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .focusSection()
    }

    private var playButton: some View {
        Button {
            onPlay(viewModel.playlist.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                Text("common.actions.play")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: 520, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brandSecondary)
        .foregroundStyle(.brandSecondaryForeground)
    }
}
