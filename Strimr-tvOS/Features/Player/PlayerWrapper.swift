import SwiftUI

struct PlayerWrapper: View {
    let viewModel: PlayerViewModel
    let onExit: () -> Void

    var body: some View {
        PlayerView(
            viewModel: viewModel,
            onExit: onExit,
        )
    }
}
