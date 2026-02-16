import SwiftUI

struct PlayerVisionWrapper: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    let launchData: PlayerLaunchData

    var body: some View {
        PlayerVisionView(
            viewModel: PlayerViewModel(
                playQueue: launchData.playQueueState,
                ratingKey: launchData.selectedRatingKey,
                context: plexApiContext,
                shouldResumeFromOffset: launchData.shouldResumeFromOffset,
            ),
            initialPlayer: .mpv,
            options: PlayerOptions(subtitleScale: settingsManager.playback.subtitleScale),
        )
    }
}
