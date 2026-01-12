import SwiftUI

struct PlayerWrapper: View {
    @Environment(SettingsManager.self) private var settingsManager
    let viewModel: PlayerViewModel
    @State private var landscapeReady = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if landscapeReady {
                if let internalPlayer = InternalPlaybackPlayer(player: settingsManager.playback.player) {
                    PlayerView(
                        viewModel: viewModel,
                        initialPlayer: internalPlayer,
                        options: PlayerOptions(subtitleScale: settingsManager.playback.subtitleScale),
                    )
                    .transition(.opacity)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task {
            AppDelegate.orientationLock = .landscape
            // MPVKit is a bit unstable and experimental, resizing is not well managed and does not display the video.
            try? await Task.sleep(for: .milliseconds(1000))
            landscapeReady = true
        }
        .onDisappear {
            AppDelegate.orientationLock = .all
        }
    }
}
