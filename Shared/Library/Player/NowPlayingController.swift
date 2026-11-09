import AetherEngine
import Combine
import Foundation
import MediaPlayer
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Publishes the playing media to the system Now Playing card and routes its remote commands back to the player.
///
/// On iOS and tvOS the engine owns the Now Playing session, which keeps the app as the active Now Playing app
/// across a background pause; commands are registered on that session. macOS has no session API, so the info
/// and commands go through the shared centers.
@MainActor
final class NowPlayingController {
    struct Commands {
        let play: () -> Void
        let pause: () -> Void
        let togglePlayPause: () -> Void
        let skip: (Double) -> Void
        let seek: (Double) -> Void
    }

    private let engine: AetherEngine
    private let commands: Commands
    private var item: NowPlayingItem?
    private var isLive = false
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var commandCenter: MPRemoteCommandCenter?
    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var cancellables: Set<AnyCancellable> = []
    #if os(macOS)
        private var requestedRate: Float = 1
        private var lastPublished: (elapsed: Double, rate: Double, date: Date)?
    #endif

    init(engine: AetherEngine, commands: Commands) {
        self.engine = engine
        self.commands = commands
        #if os(macOS)
            observePlaybackForSharedCenter()
        #else
            engine.ownsVideoNowPlayingSession = true
            engine.ownsSoftwareNowPlaying = true
            // The session is recreated with the native host, so commands move to each new one.
            engine.$currentAVPlayerItem
                .map { _ in () }
                .merge(with: engine.$videoRoute.map { _ in () })
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.attachCommandsToSession() }
                .store(in: &cancellables)
        #endif
    }

    func begin(_ item: NowPlayingItem?, isLive: Bool) {
        artworkTask?.cancel()
        self.item = item
        self.isLive = isLive
        artwork = nil
        #if !os(macOS)
            if let item {
                engine.remoteSkipInterval = item.skipForwardSeconds
            }
        #endif
        publishIdentity()
        loadArtwork()
    }

    /// Called once a load finished, when the session that will play the media exists.
    func playbackDidLoad() {
        #if os(macOS)
            attachCommands(to: item == nil ? nil : MPRemoteCommandCenter.shared())
            publishPlayback()
        #else
            attachCommandsToSession()
        #endif
    }

    func setPlaybackRate(_ rate: Float) {
        #if os(macOS)
            requestedRate = rate
            publishPlayback()
        #endif
    }

    func stop() {
        artworkTask?.cancel()
        artworkTask = nil
        item = nil
        artwork = nil
        attachCommands(to: nil)
        #if os(macOS)
            lastPublished = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        #else
            engine.setVideoNowPlayingInfo([:])
            engine.setAudioNowPlayingInfo([:])
        #endif
    }

    private func publishIdentity() {
        #if os(macOS)
            publishPlayback()
        #else
            let info = item?.identityInfo(artwork: artwork, isLive: isLive) ?? [:]
            engine.setVideoNowPlayingInfo(info)
            engine.setAudioNowPlayingInfo(info)
        #endif
    }

    private func loadArtwork() {
        guard let item, let path = item.artworkPath, let service = item.artworkService else { return }
        artworkTask = Task { [weak self] in
            guard let resource = try? await service.artwork(path: path, width: 600, height: nil) else { return }
            let data: Data? = switch resource {
            case let .data(data):
                data
            case let .url(url):
                try? await URLSession.shared.data(from: url).0
            }
            guard !Task.isCancelled, let data, let artwork = Self.makeArtwork(from: data) else { return }
            self?.artwork = artwork
            self?.publishIdentity()
        }
    }

    /// The system calls the artwork handler off the main thread, so neither may be isolated to the main actor.
    private nonisolated static func makeArtwork(from data: Data) -> MPMediaItemArtwork? {
        #if os(macOS)
            guard let image = NSImage(data: data) else { return nil }
            return MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
        #else
            guard let image = UIImage(data: data)?.preparingForDisplay() else { return nil }
            return MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
        #endif
    }

    // MARK: - Commands

    #if !os(macOS)
        private func attachCommandsToSession() {
            guard item != nil else { return }
            // The software route has no session: the engine publishes it and serves its commands itself.
            let session = engine.videoNowPlayingSession ?? engine.audioNowPlayingSession
            attachCommands(to: session?.remoteCommandCenter)
        }
    #endif

    private func attachCommands(to center: MPRemoteCommandCenter?) {
        guard center !== commandCenter else {
            updateSeekCommands()
            return
        }
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
        commandTargets.removeAll()
        commandCenter = center
        guard let center else { return }

        add(center.playCommand) { _ in .play }
        add(center.pauseCommand) { _ in .pause }
        add(center.togglePlayPauseCommand) { _ in .togglePlayPause }
        add(center.skipBackwardCommand) { event in
            (event as? MPSkipIntervalCommandEvent).map { .skip(-$0.interval) }
        }
        add(center.skipForwardCommand) { event in
            (event as? MPSkipIntervalCommandEvent).map { .skip($0.interval) }
        }
        add(center.changePlaybackPositionCommand) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { .seek($0.positionTime) }
        }
        updateSeekCommands()
    }

    private func updateSeekCommands() {
        guard let center = commandCenter else { return }
        if let item {
            center.skipBackwardCommand.preferredIntervals = [NSNumber(value: item.skipBackwardSeconds)]
            center.skipForwardCommand.preferredIntervals = [NSNumber(value: item.skipForwardSeconds)]
        }
        let canSeek = !isLive
        center.skipBackwardCommand.isEnabled = canSeek
        center.skipForwardCommand.isEnabled = canSeek
        center.changePlaybackPositionCommand.isEnabled = canSeek
    }

    private nonisolated enum Command: Sendable {
        case play
        case pause
        case togglePlayPause
        case skip(Double)
        case seek(Double)
    }

    private func add(_ command: MPRemoteCommand, _ decode: @escaping @Sendable (MPRemoteCommandEvent) -> Command?) {
        command.isEnabled = true
        let perform: @MainActor (Command) -> Void = { [weak self] in self?.perform($0) }
        // MediaPlayer may deliver commands off the main thread.
        let target = command.addTarget { @Sendable event in
            guard let decoded = decode(event) else { return .commandFailed }
            Task { @MainActor in perform(decoded) }
            return .success
        }
        commandTargets.append((command, target))
    }

    private func perform(_ command: Command) {
        guard item != nil else { return }
        switch command {
        case .play:
            commands.play()
        case .pause:
            commands.pause()
        case .togglePlayPause:
            commands.togglePlayPause()
        case let .skip(seconds):
            commands.skip(seconds)
        case let .seek(position):
            commands.seek(position)
        }
    }

    // MARK: - Shared center (macOS)

    #if os(macOS)
        private func observePlaybackForSharedCenter() {
            Publishers.CombineLatest4(engine.$state, engine.$isBuffering, engine.$duration, engine.$isLive)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.publishPlayback() }
                .store(in: &cancellables)

            engine.clock.$currentTime
                .receive(on: DispatchQueue.main)
                .sink { [weak self] position in self?.publishPlaybackIfDrifted(position: position) }
                .store(in: &cancellables)
        }

        private func publishPlaybackIfDrifted(position: Double) {
            guard let lastPublished else { return }
            let drifted = NowPlayingPlayback.hasDrifted(
                position: position,
                publishedElapsed: lastPublished.elapsed,
                publishedRate: lastPublished.rate,
                secondsSincePublish: Date().timeIntervalSince(lastPublished.date),
            )
            if drifted {
                publishPlayback()
            }
        }

        private func publishPlayback() {
            guard let item, commandCenter != nil else { return }
            let center = MPNowPlayingInfoCenter.default()
            let state = engine.state
            let elapsed = engine.clock.currentTime
            let rate = NowPlayingPlayback.rate(
                isPlaying: state == .playing,
                isBuffering: engine.isBuffering,
                requestedRate: requestedRate,
            )
            let isLive = isLive || engine.isLive
            var info = item.identityInfo(artwork: artwork, isLive: isLive)
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            info[MPNowPlayingInfoPropertyPlaybackRate] = rate
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(requestedRate)
            if !isLive, engine.duration > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = engine.duration
            }
            center.nowPlayingInfo = info
            center.playbackState = switch state {
            case .playing: .playing
            case .paused, .ended: .paused
            // Says nothing about the play or pause intent, so the card keeps the last one through a seek.
            case .loading, .seeking: center.playbackState
            case .idle, .error: .stopped
            }
            lastPublished = (elapsed, rate, Date())
        }
    #endif
}
