import Foundation

@MainActor
protocol PlaybackPresenting: AnyObject {
    func showPlayer(
        for queue: PlaybackQueue,
        services: MediaServices,
        shouldResumeFromOffset: Bool,
    )
    func showLivePlayer(context: LiveTVLaunchContext, services: MediaServices)
}

struct PlaybackLauncher {
    let services: MediaServices
    let coordinator: any PlaybackPresenting

    func play(
        ratingKey: String,
        type: MediaKind,
        shuffle: Bool = false,
        shouldResumeFromOffset: Bool = true,
    ) async {
        do {
            let queue = try await services.playback.queue(
                startingWith: ratingKey,
                kind: type,
                shuffle: shuffle,
            )
            guard !queue.items.isEmpty else { return }
            coordinator.showPlayer(
                for: queue,
                services: services,
                shouldResumeFromOffset: shouldResumeFromOffset,
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            debugPrint("Failed to create play queue:", error)
            ErrorReporter.capture(error)
        }
    }

    func using(services: MediaServices) -> PlaybackLauncher {
        PlaybackLauncher(services: services, coordinator: coordinator)
    }
}
