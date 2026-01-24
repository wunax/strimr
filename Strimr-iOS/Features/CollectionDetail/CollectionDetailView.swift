import Observation
import SwiftUI

struct CollectionDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @State var viewModel: CollectionDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onPlay: (String) -> Void

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 112, maximum: 112), spacing: 12),
        ]
    }

    init(
        viewModel: CollectionDetailViewModel,
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
            LazyVStack(alignment: .leading, spacing: 20) {
                headerSection
                playButton

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(bindableViewModel.items) { media in
                        PortraitMediaCard(media: media, width: 112, showsLabels: true) {
                            onSelectMedia(media)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
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
        HStack(alignment: .top, spacing: 16) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    context: plexApiContext,
                    artworkKind: .thumb,
                    media: viewModel.collectionDisplayItem,
                ),
            )
            .frame(width: 140, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.collection.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let elementsCountText = viewModel.elementsCountText {
                    Text(elementsCountText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let yearsText = viewModel.yearsText {
                    Text(yearsText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var playButton: some View {
        Button {
            onPlay(viewModel.collection.id)
        } label: {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.headline.weight(.semibold))
                Text("common.actions.play")
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brandSecondary)
        .foregroundStyle(.brandSecondaryForeground)
        .frame(maxWidth: .infinity)
    }
}
