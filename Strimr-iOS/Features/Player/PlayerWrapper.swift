import SwiftUI

struct PlayerWrapper: View {
    let viewModel: PlayerViewModel

    var body: some View {
        PlayerView(viewModel: viewModel)
            .transition(.opacity)
    }
}
