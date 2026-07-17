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

    var downloads: DownloadSettings {
        settings.downloads
    }

    func setAutoPlayNextEpisode(_ enabled: Bool) {
        settings.playback.autoPlayNextEpisode = enabled
        persist()
    }

    func setLosslessAudio(_ enabled: Bool) {
        settings.playback.losslessAudio = enabled
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

    func setSubtitleFontSize(_ fontSize: Int) {
        settings.playback.subtitleFontSize = fontSize
        persist()
    }

    func setSubtitleTextColor(_ color: SubtitleTextColor) {
        settings.playback.subtitleTextColor = color
        persist()
    }

    func setSubtitleFontWeight(_ weight: SubtitleFontWeight) {
        settings.playback.subtitleFontWeight = weight
        persist()
    }

    func setSubtitleBackgroundStrength(_ strength: SubtitleBackgroundStrength) {
        settings.playback.subtitleBackgroundStrength = strength
        persist()
    }

    func setSubtitleEdgeStyle(_ style: SubtitleEdgeStyle) {
        settings.playback.subtitleEdgeStyle = style
        persist()
    }

    func setSubtitleVerticalPosition(_ position: SubtitleVerticalPosition) {
        settings.playback.subtitleVerticalPosition = position
        persist()
    }

    func resetSubtitleAppearance() {
        settings.playback.resetSubtitleAppearance()
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

    func setDisplayCollections(_ enabled: Bool) {
        settings.interface.displayCollections = enabled
        persist()
    }

    func setDisplayPlaylists(_ enabled: Bool) {
        settings.interface.displayPlaylists = enabled
        persist()
    }

    func setDisplaySeerrDiscoverTab(_ enabled: Bool) {
        settings.interface.displaySeerrDiscoverTab = enabled
        persist()
    }

    func setDownloadWiFiOnly(_ enabled: Bool) {
        settings.downloads.wifiOnly = enabled
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: storageKey)
        } catch {
            ErrorReporter.capture(error)
        }
    }
}
