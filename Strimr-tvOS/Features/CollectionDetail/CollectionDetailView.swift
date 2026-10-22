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
            VStack(alignment: .leading, spacing: 48) {
                headerSection

                PosterGrid(spacing: 32, rowSpacing: 32) { cardWidth in
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
                .focusSection()
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
        .onAppear {
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await bindableViewModel.refreshIfNeeded() }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 32) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    services: mediaServices,
                    artworkKind: .thumb,
                    media: viewModel.collectionDisplayItem,
                ),
            )
            .frame(width: 280, height: 420)
            .mediaArtworkStyle(.largeDetail, borderColor: .white.opacity(0.08))

            VStack(alignment: .leading, spacing: 12) {
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

                playButtonsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .focusSection()
    }

    private var playButtonsRow: some View {
        HStack(spacing: 16) {
            Button {
                onPlay(viewModel.collection.id)
            } label: {
                Label("common.actions.play", systemImage: "play.fill")
                    .font(.facts.weight(.semibold))
                    .padding(.horizontal, 12)
            }
            .actionButtonStyle(.primary)

            Button {
                onShuffle(viewModel.collection.id)
            } label: {
                Label("common.actions.shuffle", systemImage: "shuffle")
                    .font(.facts.weight(.semibold))
                    .padding(.horizontal, 12)
            }
            .actionButtonStyle(.secondary)
        }
    }
}
