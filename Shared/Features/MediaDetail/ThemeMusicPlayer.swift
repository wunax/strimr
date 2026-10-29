import AVFoundation
import SwiftUI

struct ThemeMusic: Equatable {
    let key: String
    let url: URL

    init(path: String, url: URL, server: ServerIdentity) {
        key = "\(server.provider.rawValue)|\(server.id)|\(Self.stablePath(path))"
        self.url = url
    }

    /// Plex suffixes theme paths with a timestamp that differs between a show and its episodes
    /// (`/library/metadata/1/theme/123`), so the suffix is dropped to keep one theme playing across them.
    static func stablePath(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components[components.count - 2] == "theme",
              let last = components.last, !last.isEmpty, last.allSatisfy(\.isNumber)
        else { return path }
        return components.dropLast().joined(separator: "/")
    }
}

/// Plays the theme music of the media detail on screen, once, and keeps it going while navigating between
/// pages sharing the same theme (a show, its seasons and episodes).
@MainActor
final class ThemeMusicPlayer {
    static let shared = ThemeMusicPlayer()

    private static let releaseDelay: Duration = .milliseconds(600)
    private static let missingThemeDelay: Duration = .seconds(2)

    private var player: AVPlayer?
    private var currentKey: String?
    private var ownerID: UUID?
    private var fadeTask: Task<Void, Never>?
    private var pendingStopTask: Task<Void, Never>?

    func request(_ theme: ThemeMusic?, owner: UUID, volume: Float) {
        ownerID = owner
        pendingStopTask?.cancel()

        guard volume > 0 else {
            stopNow()
            currentKey = nil
            return
        }
        guard let theme else {
            // Pages often get their theme only once their details load.
            scheduleStop(after: Self.missingThemeDelay)
            return
        }
        if theme.key == currentKey {
            if let player {
                fade(player, to: volume)
            }
            return
        }

        fadeOutCurrent()
        let player = AVPlayer(url: theme.url)
        player.volume = 0
        player.play()
        self.player = player
        currentKey = theme.key
        fade(player, to: volume)
    }

    func release(owner: UUID) {
        guard owner == ownerID else { return }
        scheduleStop(after: Self.releaseDelay)
    }

    /// Stops right away but remembers the theme, so the page that played it does not start it over.
    func silence() {
        pendingStopTask?.cancel()
        stopNow()
    }

    private func scheduleStop(after delay: Duration) {
        pendingStopTask?.cancel()
        pendingStopTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            guard let player else {
                currentKey = nil
                return
            }
            fade(player, to: 0) { [weak self] in
                player.pause()
                self?.player = nil
                self?.currentKey = nil
            }
        }
    }

    private func stopNow() {
        fadeTask?.cancel()
        player?.pause()
        player = nil
    }

    private func fadeOutCurrent() {
        fadeTask?.cancel()
        guard let player else { return }
        self.player = nil
        Task {
            await Self.ramp(player, to: 0, duration: 0.8)
            player.pause()
        }
    }

    private func fade(_ player: AVPlayer, to volume: Float, completion: (() -> Void)? = nil) {
        fadeTask?.cancel()
        fadeTask = Task {
            await Self.ramp(player, to: volume, duration: 1.2)
            guard !Task.isCancelled else { return }
            completion?()
        }
    }

    private static func ramp(_ player: AVPlayer, to target: Float, duration: Double) async {
        let steps = 24
        let start = player.volume
        for step in 1 ... steps {
            try? await Task.sleep(for: .seconds(duration / Double(steps)))
            guard !Task.isCancelled else { return }
            player.volume = start + (target - start) * Float(step) / Float(steps)
        }
    }
}

private struct ThemeMusicModifier: ViewModifier {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(MediaServices.self) private var mediaServices
    @Environment(\.scenePhase) private var scenePhase
    @State private var ownerID = UUID()
    let media: MediaItem

    private struct Request: Equatable {
        let mediaID: String
        let themePath: String?
        let volume: ThemeMusicVolume
    }

    func body(content: Content) -> some View {
        content
            .task(id: Request(
                mediaID: media.id,
                themePath: media.themePath,
                volume: settingsManager.interface.themeMusicVolume,
            )) {
                await requestTheme()
            }
            .onDisappear {
                ThemeMusicPlayer.shared.release(owner: ownerID)
            }
            .onChange(of: scenePhase) { _, phase in
                // The app keeps its audio session in the background for picture in picture.
                if phase == .background {
                    ThemeMusicPlayer.shared.silence()
                }
            }
    }

    private func requestTheme() async {
        let volume = settingsManager.interface.themeMusicVolume.level
        // Requesting right away takes over from the previous page, so its theme keeps playing during the lookup.
        ThemeMusicPlayer.shared.request(theme(path: media.themePath), owner: ownerID, volume: volume)
        // Some providers fetch the theme separately, so nothing is requested while theme music is off.
        guard volume > 0 else { return }
        let path = await mediaServices.artwork.themePath(for: media)
        guard !Task.isCancelled, path != media.themePath else { return }
        ThemeMusicPlayer.shared.request(theme(path: path), owner: ownerID, volume: volume)
    }

    private func theme(path: String?) -> ThemeMusic? {
        path.flatMap { path in
            mediaServices.artwork.themeMusicURL(path: path).map {
                ThemeMusic(path: path, url: $0, server: mediaServices.identity)
            }
        }
    }
}

extension View {
    func themeMusic(for media: MediaItem) -> some View {
        modifier(ThemeMusicModifier(media: media))
    }
}
