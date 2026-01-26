import Foundation

struct PlaybackLauncher {
    let context: PlexAPIContext
    let coordinator: MainCoordinator
    let settingsManager: SettingsManager
    let openURL: (URL) -> Void

    func play(
        ratingKey: String,
        type: PlexItemType,
        shuffle: Bool = false,
        shouldResumeFromOffset: Bool = true,
    ) async {
        do {
            let manager = try PlayQueueManager(context: context)
            let playQueue = try await manager.createQueue(
                for: ratingKey,
                itemType: type,
                continuous: type == .episode || type == .show || type == .season,
                shuffle: shuffle,
            )

            guard let selectedRatingKey = playQueue.selectedRatingKey else {
                return
            }

            if settingsManager.playback.player.isExternal {
                await launchExternalPlayback(ratingKey: selectedRatingKey)
            } else {
                await MainActor.run {
                    coordinator.showPlayer(for: playQueue, shouldResumeFromOffset: shouldResumeFromOffset)
                }
            }
        } catch {
            debugPrint("Failed to create play queue:", error)
            ErrorReporter.capture(error)
        }
    }

    @MainActor
    private func launchExternalPlayback(ratingKey: String) async {
        do {
            let launcher = ExternalPlaybackLauncher(context: context)
            let infuseURL = try await launcher.infuseURL(for: ratingKey)
            openURL(infuseURL)
        } catch {
            debugPrint("Failed to launch external playback:", error)
        }
    }
}
