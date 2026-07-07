import SwiftUI

struct PlayerTVWrapper: View {
    let viewModel: PlayerViewModel
    let onExit: () -> Void

    var body: some View {
        PlayerTVView(
            viewModel: viewModel,
            onExit: onExit,
        )
    }
}
