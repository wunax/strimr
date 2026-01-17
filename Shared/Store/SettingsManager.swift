import Foundation
import Observation

@MainActor
@Observable
final class SettingsManager {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "strimr.settings"

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

    var interface: InterfaceSettings {
        settings.interface
    }

    var download: DownloadSettings {
        settings.download
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

    func setSubtitleScale(_ scale: Int) {
        settings.playback.subtitleScale = scale
        persist()
    }

    func updatePlayback(_ transform: (inout PlaybackSettings) -> Void) {
        transform(&settings.playback)
        persist()
    }

    func setHiddenLibraryIds(_ ids: [String]) {
        settings.interface.hiddenLibraryIds = ids.sorted()
        persist()
    }

    func setLibraryDisplayed(_ libraryId: String, displayed: Bool) {
        var hiddenIds = Set(settings.interface.hiddenLibraryIds)
        if displayed {
            hiddenIds.remove(libraryId)
        } else {
            hiddenIds.insert(libraryId)
        }
        settings.interface.hiddenLibraryIds = hiddenIds.sorted()
        persist()
    }

    func setNavigationLibraryIds(_ ids: [String]) {
        settings.interface.navigationLibraryIds = ids
        persist()
    }

    func setShowDownloadsAfterMovieDownload(_ enabled: Bool) {
        settings.download.showDownloadsAfterMovieDownload = enabled
        persist()
    }

    func setShowDownloadsAfterEpisodeDownload(_ enabled: Bool) {
        settings.download.showDownloadsAfterEpisodeDownload = enabled
        persist()
    }

    func setShowDownloadsAfterShowDownload(_ enabled: Bool) {
        settings.download.showDownloadsAfterShowDownload = enabled
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
