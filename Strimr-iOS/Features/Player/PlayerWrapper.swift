import SwiftUI

struct PlayerWrapper: View {
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    let viewModel: PlayerViewModel

    var body: some View {
        PlayerView(viewModel: viewModel)
            .transition(.opacity)
            .handoffPlayback(sharePlayCoordinator.isInSession ? nil : viewModel.handoffMedia)
    }
}
