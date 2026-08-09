import Foundation

@MainActor
protocol PlaybackPresenting: AnyObject {
    func showPlayer(
        for playQueue: PlayQueueState,
        context: PlexAPIContext,
        shouldResumeFromOffset: Bool,
    )

    func showPlayer(
        for queue: PlaybackQueue,
        services: MediaServices,
        shouldResumeFromOffset: Bool,
    )
}

struct PlaybackLauncher {
    let services: MediaServices
    let coordinator: any PlaybackPresenting

    init(services: MediaServices, coordinator: any PlaybackPresenting) {
        self.services = services
        self.coordinator = coordinator
    }

    init?(context: PlexAPIContext, coordinator: any PlaybackPresenting) {
        guard let services = PlexMediaServicesFactory.make(context: context, sessionManager: nil) else {
            return nil
        }
        self.init(services: services, coordinator: coordinator)
    }

    func play(
        ratingKey: String,
        type: MediaKind,
        shuffle: Bool = false,
        shouldResumeFromOffset: Bool = true,
    ) async {
        do {
            if let context = services.plexContext {
                let manager = try PlayQueueManager(context: context)
                let playQueue = try await manager.createQueue(
                    for: ratingKey,
                    itemType: type.plexType,
                    continuous: type == .episode || type == .series || type == .season,
                    shuffle: shuffle,
                )
                guard playQueue.selectedRatingKey != nil else { return }
                coordinator.showPlayer(
                    for: playQueue,
                    context: context,
                    shouldResumeFromOffset: shouldResumeFromOffset,
                )
            } else {
                let queue = try await services.playback.queue(
                    startingWith: ratingKey,
                    kind: type,
                    shuffle: shuffle
                )
                guard !queue.items.isEmpty else { return }
                coordinator.showPlayer(
                    for: queue,
                    services: services,
                    shouldResumeFromOffset: shouldResumeFromOffset
                )
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            debugPrint("Failed to create play queue:", error)
            ErrorReporter.capture(error)
        }
    }

    func using(services: MediaServices) -> PlaybackLauncher {
        PlaybackLauncher(services: services, coordinator: coordinator)
    }

    func using(context: PlexAPIContext) -> PlaybackLauncher? {
        PlaybackLauncher(context: context, coordinator: coordinator)
    }
}
