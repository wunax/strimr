import SwiftUI

struct HubDetailView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State var viewModel: HubDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private var columnSpacing: CGFloat {
        #if os(tvOS)
            32
        #else
            12
        #endif
    }

    var body: some View {
        ScrollView {
            PosterGrid(spacing: columnSpacing, rowSpacing: gridSpacing) { cardWidth in
                if viewModel.isLoading, viewModel.items.isEmpty {
                    PosterSkeletonCards(width: cardWidth, showsLabels: settingsManager.interface.showsCardLabels)
                }
                ForEach(viewModel.items, id: \.id) { item in
                    PortraitMediaCard(
                        media: item,
                        width: cardWidth,
                        showsLabels: settingsManager.interface.showsCardLabels,
                    ) {
                        onSelectMedia(item)
                    }
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItem: item)
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(width: cardWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .navigationTitle(viewModel.hub.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .overlay {
                if viewModel.isLoading, viewModel.items.isEmpty {
                    EmptyView()
                } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater"),
                    )
                    .symbolRenderingMode(.multicolor)
                } else if viewModel.items.isEmpty, !viewModel.isLoading {
                    ContentUnavailableView(
                        "hub.empty",
                        systemImage: "square.grid.2x2.fill",
                    )
                }
            }
            .task {
                await viewModel.load()
            }
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
            32
        #else
            16
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            48
        #else
            16
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            48
        #else
            16
        #endif
    }
}
