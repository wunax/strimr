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

    func setNextEpisodeAutoplay(_ autoplay: NextEpisodeAutoplay) {
        settings.playback.nextEpisodeAutoplay = autoplay
        persist()
    }

    func setPlaybackQualityPreset(_ preset: TranscodeQualityPreset) {
        settings.playback.qualityPreset = preset
        persist()
    }

    func setAutoSkipIntros(_ enabled: Bool) {
        settings.playback.autoSkipIntros = enabled
        persist()
    }

    func setAutoSkipCredits(_ enabled: Bool) {
        settings.playback.autoSkipCredits = enabled
        persist()
    }

    func setLosslessAudio(_ enabled: Bool) {
        settings.playback.losslessAudio = enabled
        persist()
    }

    func setRememberTrackSelections(_ enabled: Bool) {
        settings.playback.rememberTrackSelections = enabled
        persist()
    }

    func setShowChaptersOnTimeline(_ enabled: Bool) {
        settings.playback.showChaptersOnTimeline = enabled
        persist()
    }

    func setShowEndsAtTime(_ enabled: Bool) {
        settings.playback.showEndsAtTime = enabled
        persist()
    }

    func setShowClock(_ enabled: Bool) {
        settings.playback.showClock = enabled
        persist()
    }

    func setShowScrubThumbnailPreviews(_ enabled: Bool) {
        settings.playback.showScrubThumbnailPreviews = enabled
        persist()
    }

    func setGenerateMissingScrubThumbnailPreviews(_ enabled: Bool) {
        settings.playback.generateMissingScrubThumbnailPreviews = enabled
        persist()
    }

    func setStyledASSSubtitles(_ enabled: Bool) {
        settings.playback.styledASSSubtitles = enabled
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

    func setAudioDelayMilliseconds(_ milliseconds: Int) {
        settings.playback.audioDelayMilliseconds = PlaybackOffsetRange.audio.clamp(milliseconds)
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

    func homeRowPreferences(for scopeID: String) -> HomeRowPreferences {
        settings.interface.homeRowsByScope[scopeID] ?? HomeRowPreferences()
    }

    func setHomeRowVisibility(_ rowID: String, visible: Bool, scopeID: String) {
        var preferences = homeRowPreferences(for: scopeID)
        preferences.setRow(rowID, visible: visible)
        settings.interface.homeRowsByScope[scopeID] = preferences
        persist()
    }

    func setHomeRowOrder(_ rowIDs: [String], scopeID: String) {
        var preferences = homeRowPreferences(for: scopeID)
        preferences.setOrder(rowIDs)
        settings.interface.homeRowsByScope[scopeID] = preferences
        persist()
    }

    func resetHomeRows(scopeID: String) {
        settings.interface.homeRowsByScope.removeValue(forKey: scopeID)
        persist()
    }

    // MARK: - Home rows (per profile)

    func homeRowPreferences(profileID: String) -> HomeRowPreferences {
        settings.interface.homeRowsByProfile[profileID] ?? HomeRowPreferences()
    }

    func setHomeRowVisibility(_ rowID: String, visible: Bool, profileID: String) {
        var preferences = homeRowPreferences(profileID: profileID)
        preferences.setRow(rowID, visible: visible)
        settings.interface.homeRowsByProfile[profileID] = preferences
        persist()
    }

    func setHomeRowOrder(_ rowIDs: [String], profileID: String) {
        var preferences = homeRowPreferences(profileID: profileID)
        preferences.setOrder(rowIDs)
        settings.interface.homeRowsByProfile[profileID] = preferences
        persist()
    }

    func resetHomeRows(profileID: String) {
        settings.interface.homeRowsByProfile.removeValue(forKey: profileID)
        persist()
    }

    // MARK: - Libraries (per profile)

    func libraryPreferences(profileID: String) -> LibraryPreferences {
        settings.interface.librariesByProfile[profileID] ?? LibraryPreferences()
    }

    func updateLibraryPreferences(profileID: String, _ transform: (inout LibraryPreferences) -> Void) {
        var preferences = libraryPreferences(profileID: profileID)
        transform(&preferences)
        guard preferences != libraryPreferences(profileID: profileID) else { return }
        settings.interface.librariesByProfile[profileID] = preferences.isEmpty ? nil : preferences
        persist()
    }

    /// Forgets the libraries a server stopped returning, for every profile. Only call it after a successful load.
    func pruneLibraries(of server: ServerIdentity, keeping libraryIDs: Set<String>) {
        var changed = false
        for (profileID, preferences) in settings.interface.librariesByProfile {
            var pruned = preferences
            pruned.pruneLibraries(of: server, keeping: libraryIDs)
            if pruned != preferences {
                settings.interface.librariesByProfile[profileID] = pruned.isEmpty ? nil : pruned
                changed = true
            }
        }
        if changed {
            persist()
        }
    }

    // MARK: - Cleanup

    /// Removes the rows and libraries of servers whose account was removed, for every profile. Servers that are only
    /// unreachable or disabled must keep their settings.
    func removeSettings(of servers: Set<ServerIdentity>) {
        guard !servers.isEmpty else { return }
        for (profileID, preferences) in settings.interface.homeRowsByProfile {
            var cleaned = preferences
            cleaned.removeRows(of: servers)
            settings.interface.homeRowsByProfile[profileID] = cleaned.isEmpty ? nil : cleaned
        }
        for (profileID, preferences) in settings.interface.librariesByProfile {
            var cleaned = preferences
            cleaned.removeLibraries(of: servers)
            settings.interface.librariesByProfile[profileID] = cleaned.isEmpty ? nil : cleaned
        }
        persist()
    }

    func removeSettings(profileID: String) {
        settings.interface.homeRowsByProfile[profileID] = nil
        settings.interface.librariesByProfile[profileID] = nil
        persist()
    }

    func updateInterface(_ transform: (inout InterfaceSettings) -> Void) {
        transform(&settings.interface)
        persist()
    }

    func libraryBrowsePreferences(for key: String) -> LibraryBrowsePreferences {
        settings.interface.libraryBrowseByKey[key] ?? LibraryBrowsePreferences()
    }

    func setLibraryBrowsePreferences(_ preferences: LibraryBrowsePreferences, for key: String) {
        guard settings.interface.libraryBrowseByKey[key] != preferences else { return }
        settings.interface.libraryBrowseByKey[key] = preferences
        persist()
    }

    var customLibraryLayoutCount: Int {
        settings.interface.libraryBrowseByKey.values.count { $0.layout != nil }
    }

    func resetLibraryLayouts() {
        for (key, preferences) in settings.interface.libraryBrowseByKey where preferences.layout != nil {
            var preferences = preferences
            preferences.layout = nil
            settings.interface.libraryBrowseByKey[key] = preferences == LibraryBrowsePreferences() ? nil : preferences
        }
        persist()
    }

    func setLibraryDefaultLayout(_ layout: LibraryDefaultLayout) {
        settings.interface.libraryDefaultLayout = layout
        persist()
    }

    func setPosterSize(_ size: PosterSize) {
        settings.interface.posterSize = size
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

    func setDisplayFavoritesTab(_ enabled: Bool) {
        settings.interface.displayFavoritesTab = enabled
        persist()
    }

    func setDisplayDownloadsTab(_ enabled: Bool) {
        settings.interface.displayDownloadsTab = enabled
        persist()
    }

    func setDisplayLiveTVTab(_ enabled: Bool) {
        settings.interface.displayLiveTVTab = enabled
        persist()
    }

    func setDisplaySeerrDiscoverTab(_ enabled: Bool) {
        settings.interface.displaySeerrDiscoverTab = enabled
        persist()
    }

    func setMultiServerSearchEnabled(_ enabled: Bool) {
        settings.interface.multiServerSearchEnabled = enabled
        persist()
    }

    func setSpoilerProtection(_ level: SpoilerProtectionLevel) {
        settings.interface.spoilerProtection = level
        persist()
    }

    func setDownloadWiFiOnly(_ enabled: Bool) {
        settings.downloads.wifiOnly = enabled
        persist()
    }

    func setDownloadQualityPreset(_ preset: TranscodeQualityPreset) {
        settings.downloads.qualityPreset = preset
        persist()
    }

    func setOfflineCacheLimit(megabytes: Int) {
        settings.downloads.offlineCacheLimitMB = megabytes
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
