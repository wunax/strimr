import Foundation

@MainActor
protocol PlaybackPresenting: AnyObject {
    func showPlayer(
        for playQueue: PlayQueueState,
        context: PlexAPIContext,
        shouldResumeFromOffset: Bool,
    )
}

struct PlaybackLauncher {
    let context: PlexAPIContext
    let coordinator: any PlaybackPresenting

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
                coordinator.showPlayer(
                    for: playQueue,
                    context: context,
                    shouldResumeFromOffset: shouldResumeFromOffset,
                )
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            debugPrint("Failed to create play queue:", error)
            ErrorReporter.capture(error)
        }
    }

    func using(context: PlexAPIContext) -> PlaybackLauncher {
        PlaybackLauncher(context: context, coordinator: coordinator)
    }
}
