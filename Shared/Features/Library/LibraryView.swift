import SwiftUI

struct LibraryView: View {
    @State var viewModel: LibraryViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: LibraryViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        LibraryTileGrid(viewModel: viewModel)
            .navigationTitle("tabs.libraries")
    }
}
