import Foundation

@MainActor
protocol PlaybackPresenting: AnyObject {
    func showPlayer(
        for queue: PlaybackQueue,
        services: MediaServices,
        shouldResumeFromOffset: Bool,
    )
    func showLivePlayer(context: LiveTVLaunchContext, services: MediaServices)
    #if !os(tvOS)
        func showLocalPlayer(_ request: LocalPlaybackRequest)
    #endif
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
        #if !os(tvOS)
            // Without the server, the downloaded copy is played instead of streaming.
            if !shuffle, OfflineCoordinator.shared.isUnreachable(services.identity) {
                playDownloaded(ratingKey: ratingKey, type: type, shouldResumeFromOffset: shouldResumeFromOffset)
                return
            }
        #endif
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

    #if !os(tvOS)
        /// Plays the downloaded file of a movie or episode, or the next downloaded episode of a series or season.
        @discardableResult
        func playDownloaded(ratingKey: String, type: MediaKind, shouldResumeFromOffset: Bool = true) -> Bool {
            guard let request = DownloadManager.shared?.localPlaybackRequest(
                for: MediaIdentity(server: services.identity, itemID: ratingKey),
                kind: type,
                resumes: shouldResumeFromOffset,
            ) else { return false }
            coordinator.showLocalPlayer(request)
            return true
        }
    #endif

    func using(services: MediaServices) -> PlaybackLauncher {
        PlaybackLauncher(services: services, coordinator: coordinator)
    }
}
