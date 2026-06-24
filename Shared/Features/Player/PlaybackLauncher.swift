import Foundation

struct PlaybackLauncher {
    let context: PlexAPIContext
    let coordinator: MainCoordinator

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

            guard playQueue.selectedRatingKey != nil else {
                return
            }

            await MainActor.run {
                coordinator.showPlayer(for: playQueue, shouldResumeFromOffset: shouldResumeFromOffset)
            }
        } catch {
            debugPrint("Failed to create play queue:", error)
            ErrorReporter.capture(error)
        }
    }
}
