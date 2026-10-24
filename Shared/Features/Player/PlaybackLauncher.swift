import Foundation

@MainActor
protocol PlaybackPresenting: AnyObject {
    /// Player chosen in the settings for on-demand playback, nil for the built-in player.
    var externalPlayer: ExternalPlayer? { get }
    func showPlayer(
        for queue: PlaybackQueue,
        services: MediaServices,
        shouldResumeFromOffset: Bool,
        notice: String?,
    )
    func showLivePlayer(context: LiveTVLaunchContext, services: MediaServices)
    #if !os(tvOS)
        func showLocalPlayer(_ request: LocalPlaybackRequest)
    #endif
    /// Whether the external app opened.
    func openExternalPlayer(_ request: ExternalLaunchRequest) async -> Bool
}

struct PlaybackLauncher {
    let services: MediaServices
    let coordinator: any PlaybackPresenting

    /// - Parameter allowsExternalPlayer: false keeps the built-in player, which SharePlay needs to stay in sync.
    func play(
        ratingKey: String,
        type: MediaKind,
        shuffle: Bool = false,
        shouldResumeFromOffset: Bool = true,
        allowsExternalPlayer: Bool = true,
    ) async {
        ThemeMusicPlayer.shared.silence()
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
            await present(
                queue,
                shouldResumeFromOffset: shouldResumeFromOffset,
                allowsExternalPlayer: allowsExternalPlayer,
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            debugPrint("Failed to create play queue:", error)
            ErrorReporter.capture(error)
        }
    }

    /// Plays the playlist in its order from `entry`, the entries before it staying in the queue.
    func playPlaylist(id: String, startingWith entry: PlaylistEntry) async {
        ThemeMusicPlayer.shared.silence()
        #if !os(tvOS)
            if OfflineCoordinator.shared.isUnreachable(services.identity) {
                playDownloaded(ratingKey: entry.media.id, type: entry.media.type)
                return
            }
        #endif
        do {
            let queue = try await services.playback.queue(playlistID: id, startingWith: entry)
            await present(queue, shouldResumeFromOffset: true, allowsExternalPlayer: true)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }

    private func present(
        _ queue: PlaybackQueue,
        shouldResumeFromOffset: Bool,
        allowsExternalPlayer: Bool,
    ) async {
        guard !queue.items.isEmpty else { return }
        if allowsExternalPlayer,
           let player = coordinator.externalPlayer,
           player.isSupported(on: .current)
        {
            await playExternally(queue: queue, player: player, shouldResumeFromOffset: shouldResumeFromOffset)
            return
        }
        coordinator.showPlayer(
            for: queue,
            services: services,
            shouldResumeFromOffset: shouldResumeFromOffset,
            notice: nil,
        )
    }

    /// Only the item the built-in player would start with is handed over; the rest of the queue is not played.
    private func playExternally(
        queue: PlaybackQueue,
        player: ExternalPlayer,
        shouldResumeFromOffset: Bool,
    ) async {
        let media = queue.items.indices.contains(queue.currentIndex)
            ? queue.items[queue.currentIndex].media
            : queue.items[0].media
        let fallbackNotice = String(localized: "player.external.launchFailed \(player.displayName)")
        var target: ExternalPlaybackTarget
        do {
            target = try await services.playback.externalPlaybackTarget(
                for: media,
                version: services.versionRequest(for: media),
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            coordinator.showPlayer(
                for: queue,
                services: services,
                shouldResumeFromOffset: shouldResumeFromOffset,
                notice: fallbackNotice,
            )
            return
        }
        if shouldResumeFromOffset {
            target.startPosition = media.viewOffset ?? 0
        }
        if let request = player.launchRequest(for: target, platform: .current),
           await coordinator.openExternalPlayer(request)
        {
            return
        }
        coordinator.showPlayer(
            for: queue,
            services: services,
            shouldResumeFromOffset: shouldResumeFromOffset,
            notice: fallbackNotice,
        )
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
