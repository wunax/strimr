import SwiftUI

struct PlayerWrapper: View {
    @Environment(SettingsManager.self) private var settingsManager
    let viewModel: PlayerViewModel
    let onExit: () -> Void

    var body: some View {
        PlayerView(
            viewModel: viewModel,
            controlsStyle: settingsManager.playback.playerControlsStyle,
            onExit: onExit,
        )
    }
}
