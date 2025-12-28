import Foundation
import Observation

@MainActor
@Observable
final class SettingsManager {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "dev.strimr.app.settings"

    private(set) var settings: AppSettings

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = stored
        } else {
            settings = AppSettings()
        }
    }

    var playback: PlaybackSettings {
        settings.playback
    }

    func setAutoPlayNextEpisode(_ enabled: Bool) {
        settings.playback.autoPlayNextEpisode = enabled
        persist()
    }

    func setSeekBackwardSeconds(_ seconds: Int) {
        settings.playback.seekBackwardSeconds = seconds
        persist()
    }

    func setSeekForwardSeconds(_ seconds: Int) {
        settings.playback.seekForwardSeconds = seconds
        persist()
    }

    func setPlaybackPlayer(_ player: PlaybackPlayer) {
        settings.playback.player = player
        persist()
    }

    func updatePlayback(_ transform: (inout PlaybackSettings) -> Void) {
        transform(&settings.playback)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
