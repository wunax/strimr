import SwiftUI

extension MainTabView {
    func handlePlay(ratingKey: String, shouldResumeFromOffset: Bool = true, downloadPath: String? = nil) {
        let player = settingsManager.playback.player
        if player.isExternal {
            Task { @MainActor in
                await launchExternalPlayback(ratingKey: ratingKey)
            }
        } else {
            coordinator.showPlayer(for: ratingKey, shouldResumeFromOffset: shouldResumeFromOffset, downloadPath: downloadPath)
        }
    }

    @MainActor
    func launchExternalPlayback(ratingKey: String) async {
        do {
            let launcher = ExternalPlaybackLauncher(
                context: plexApiContext,
            )
            let infuseURL = try await launcher.infuseURL(for: ratingKey)
            openURL(infuseURL)
        } catch {
            debugPrint("Failed to launch external playback:", error)
        }
    }
}
