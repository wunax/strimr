import SwiftUI

struct HubDetailView: View {
    @State var viewModel: HubDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private var gridColumns: [GridItem] {
        #if os(tvOS)
            [
                GridItem(.adaptive(minimum: 200, maximum: 200), spacing: 32, alignment: .top),
            ]
        #else
            [
                GridItem(.adaptive(minimum: 112, maximum: 112), spacing: 12, alignment: .top),
            ]
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(viewModel.items, id: \.id) { item in
                    PortraitMediaCard(media: item, width: cardWidth, showsLabels: true) {
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
                    ProgressView("hub.loading")
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

    private var cardWidth: CGFloat {
        #if os(tvOS)
            200
        #else
            112
        #endif
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
