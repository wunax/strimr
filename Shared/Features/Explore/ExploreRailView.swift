import SwiftUI

/// Everything behind a rail's See All.
struct ExploreRailView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State private var viewModel: ExploreRailViewModel
    let onSelect: (ExploreItem) -> Void

    init(viewModel: ExploreRailViewModel, onSelect: @escaping (ExploreItem) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView {
            PosterGrid(spacing: spacing, rowSpacing: spacing) { cardWidth in
                ForEach(viewModel.items) { item in
                    ExploreItemCard(
                        item: item,
                        width: cardWidth,
                        showsLabels: settingsManager.interface.showsCardLabels,
                    ) {
                        onSelect(item)
                    }
                }
                if viewModel.isLoading {
                    ProgressView()
                        .frame(width: cardWidth)
                }
            }
            .padding(.horizontal, LayoutMetrics.pageMargin)
            .padding(.vertical, 20)
        }
        .navigationTitle(viewModel.rail.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .overlay {
                if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle.fill")
                }
            }
            .task {
                await viewModel.load()
            }
    }

    private var spacing: CGFloat {
        #if os(tvOS)
            32
        #else
            16
        #endif
    }
}
