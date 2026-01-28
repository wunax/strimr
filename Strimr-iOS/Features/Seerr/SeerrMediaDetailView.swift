import SwiftUI

@MainActor
struct SeerrMediaDetailView: View {
    @State var viewModel: SeerrMediaDetailViewModel

    init(viewModel: SeerrMediaDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        EmptyView()
    }
}
