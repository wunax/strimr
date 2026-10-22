import Observation
import SwiftUI

struct CollectionDetailView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(MediaServices.self) private var mediaServices
    @Environment(\.scenePhase) private var scenePhase
    @State var viewModel: CollectionDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onPlay: (String) -> Void
    let onShuffle: (String) -> Void

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
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                headerSection
                playButtonsRow

                PosterGrid(spacing: 12, rowSpacing: 16) { cardWidth in
                    ForEach(bindableViewModel.items) { media in
                        PortraitMediaCard(
                            media: media,
                            width: cardWidth,
                            showsLabels: settingsManager.interface.showsCardLabels,
                        ) {
                            onSelectMedia(media)
                        }
                    }
                }
            }
            .padding(.horizontal, LayoutMetrics.pageMargin)
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
        .onAppear {
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await bindableViewModel.refreshIfNeeded() }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    services: mediaServices,
                    artworkKind: .thumb,
                    media: viewModel.collectionDisplayItem,
                ),
            )
            .frame(width: 140, height: 210)
            .mediaArtworkStyle()

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.collection.title)
                    .font(.tileTitle)
                    .foregroundStyle(.textPrimary)

                if let elementsCountText = viewModel.elementsCountText {
                    Text(elementsCountText)
                        .font(.facts)
                        .foregroundStyle(.textSecondary)
                }

                if let yearsText = viewModel.yearsText {
                    Text(yearsText)
                        .font(.facts)
                        .foregroundStyle(.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var playButtonsRow: some View {
        HStack(spacing: 12) {
            Button {
                onPlay(viewModel.collection.id)
            } label: {
                Label("common.actions.play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .actionButtonStyle(.primary)

            Button {
                onShuffle(viewModel.collection.id)
            } label: {
                Image(systemName: "shuffle")
            }
            .actionButtonStyle(.secondary)
            .accessibilityLabel(Text("common.actions.shuffle"))
        }
    }
}
