import Foundation
@testable import Strimr
import Testing

struct AppSettingsTests {
    @Test func `missing library browse preferences decode as empty`() throws {
        let settings = try decode(#"{"interface":{"displayPlaylists":false}}"#)

        #expect(settings.interface.libraryBrowseByKey.isEmpty)
        #expect(!settings.interface.displayPlaylists)
    }

    @Test func `theme music is off unless chosen`() throws {
        #expect(try decode(#"{"interface":{}}"#).interface.themeMusicVolume == .off)
        #expect(try decode(#"{"interface":{"themeMusicVolume":"loud"}}"#).interface.themeMusicVolume == .off)
        #expect(try decode(#"{"interface":{"themeMusicVolume":"medium"}}"#).interface.themeMusicVolume == .medium)
    }

    @Test func `title logo is shown unless turned off`() throws {
        #expect(try decode(#"{"interface":{"displayPlaylists":false}}"#).interface.showsTitleLogo)
        #expect(try !decode(#"{"interface":{"showsTitleLogo":false}}"#).interface.showsTitleLogo)
    }

    @Test func `card labels are shown unless turned off`() throws {
        #expect(try decode(#"{"interface":{"displayPlaylists":false}}"#).interface.showsCardLabels)
        #expect(try !decode(#"{"interface":{"showsCardLabels":false}}"#).interface.showsCardLabels)
    }

    @Test func `corrupt library browse preferences keep other settings`() throws {
        let settings = try decode(#"""
        {"interface":{"displayPlaylists":false,"libraryBrowseByKey":{"plex|server|account|1":{"plex":{"filters":42}}}}}
        """#)

        #expect(settings.interface.libraryBrowseByKey.isEmpty)
        #expect(!settings.interface.displayPlaylists)
    }

    @Test func `library browse preferences survive a round trip`() throws {
        var query = LibraryBrowseQuery()
        query.sort = .dateAdded
        query.sortDirection = .descending
        query.watchStatus = .unplayed
        query.isFavorite = true
        query.genreIDs = ["genre"]
        query.years = [1999, 2024]
        let preferences = LibraryBrowsePreferences(
            plex: .init(
                displayTypeKey: "/library/sections/1/all?type=1",
                sortKey: "addedAt",
                sortDirection: .desc,
                sortQueryValue: "addedAt:desc",
                filters: ["genre": .init(isEnabled: true, optionKey: "28", optionFastKey: nil, optionTitle: "Action")],
            ),
            jellyfinQuery: query,
        )
        var settings = AppSettings()
        settings.interface.libraryBrowseByKey["key"] = preferences

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.interface.libraryBrowseByKey["key"] == preferences)
    }

    @MainActor
    @Test func `saved library browse preferences survive a reload`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        var preferences = LibraryBrowsePreferences()
        preferences.plex = .init(sortKey: "addedAt", sortDirection: .desc, sortQueryValue: "addedAt:desc")

        SettingsManager(userDefaults: defaults).setLibraryBrowsePreferences(preferences, for: "key")
        let reloaded = SettingsManager(userDefaults: defaults)

        #expect(reloaded.libraryBrowsePreferences(for: "key") == preferences)
    }

    @Test func `missing pause screen setting decodes as enabled`() throws {
        let settings = try decode(#"{"playback":{"showClock":true}}"#)

        #expect(settings.playback.showInfoWhenPaused)
        #expect(settings.playback.showClock)
    }

    @Test func `missing library display defaults decode as automatic and medium`() throws {
        let settings = try decode(#"{"interface":{"libraryDefaultLayout":"mosaic"}}"#)

        #expect(settings.interface.libraryDefaultLayout == .automatic)
        #expect(settings.interface.posterSize == .medium)
    }

    @MainActor
    @Test func `resetting library layouts keeps sort and filters`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let manager = SettingsManager(userDefaults: defaults)
        var withSelection = LibraryBrowsePreferences(layout: .list)
        withSelection.plex = .init(sortKey: "addedAt")
        manager.setLibraryBrowsePreferences(withSelection, for: "a")
        manager.setLibraryBrowsePreferences(LibraryBrowsePreferences(layout: .grid), for: "b")
        #expect(manager.customLibraryLayoutCount == 2)

        manager.resetLibraryLayouts()

        #expect(manager.customLibraryLayoutCount == 0)
        #expect(manager.libraryBrowsePreferences(for: "a").plex?.sortKey == "addedAt")
        #expect(manager.interface.libraryBrowseByKey["b"] == nil)
    }

    @Test func `missing audio delay decodes as zero`() throws {
        let settings = try decode(#"{"playback":{"losslessAudio":true}}"#)

        #expect(settings.playback.audioDelayMilliseconds == 0)
        #expect(settings.playback.losslessAudio)
    }

    @Test func `out of range audio delay decodes clamped`() throws {
        #expect(try decode(#"{"playback":{"audioDelayMilliseconds":9000}}"#).playback.audioDelayMilliseconds == 2000)
        #expect(try decode(#"{"playback":{"audioDelayMilliseconds":-9000}}"#).playback.audioDelayMilliseconds == -2000)
    }

    @Test func `corrupt audio delay keeps other settings`() throws {
        let settings = try decode(#"{"playback":{"audioDelayMilliseconds":"late","seekForwardSeconds":30}}"#)

        #expect(settings.playback.audioDelayMilliseconds == 0)
        #expect(settings.playback.seekForwardSeconds == 30)
    }

    @Test func `subtitle brightness is full unless chosen`() throws {
        #expect(try decode(#"{"playback":{}}"#).playback.subtitleBrightness == .full)
        #expect(try decode(#"{"playback":{"subtitleBrightness":"medium"}}"#).playback.subtitleBrightness == .medium)
    }

    @Test func `unknown subtitle brightness keeps other subtitle settings`() throws {
        let settings = try decode(#"{"playback":{"subtitleBrightness":"dim","subtitleTextColor":"cream"}}"#)

        #expect(settings.playback.subtitleBrightness == .full)
        #expect(settings.playback.subtitleTextColor == .cream)
    }

    @Test func `resetting subtitle appearance restores full brightness`() {
        var playback = PlaybackSettings()
        playback.subtitleBrightness = .low
        playback.subtitleTextColor = .lightGray

        playback.resetSubtitleAppearance()

        #expect(playback.subtitleBrightness == .full)
        #expect(playback.subtitleTextColor == .white)
    }

    @MainActor
    @Test func `saved audio delay survives a reload`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }

        SettingsManager(userDefaults: defaults).setAudioDelayMilliseconds(-350)

        #expect(SettingsManager(userDefaults: defaults).playback.audioDelayMilliseconds == -350)
    }

    @Test func `missing external player settings decode as the built-in player`() throws {
        let settings = try decode(#"{"playback":{"showClock":true}}"#)

        #expect(settings.playback.externalPlayer == nil)
        #expect(settings.playback.customExternalPlayer == nil)
        #expect(settings.playback.resolvedExternalPlayer == nil)
        #expect(settings.playback.showClock)
    }

    @Test func `external player settings survive a round trip`() throws {
        var settings = AppSettings()
        settings.playback.externalPlayer = .known(.infuse)

        var decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.playback.externalPlayer == .known(.infuse))

        let custom = CustomExternalPlayer(name: "Mine", template: "mine://play?url={url}")
        settings.playback.externalPlayer = .custom
        settings.playback.customExternalPlayer = custom
        decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.playback.externalPlayer == .custom)
        #expect(decoded.playback.customExternalPlayer == custom)
        #expect(decoded.playback.resolvedExternalPlayer == .custom(custom))
    }

    @Test func `corrupt external player keeps other settings`() throws {
        let settings = try decode(#"{"playback":{"externalPlayer":{"known":{"_0":"mpv"}},"showClock":true}}"#)

        #expect(settings.playback.externalPlayer == nil)
        #expect(settings.playback.showClock)
    }

    @MainActor
    @Test func `custom player is kept after switching players`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let manager = SettingsManager(userDefaults: defaults)
        let custom = CustomExternalPlayer(name: "Mine", template: "mine://play?url={url}")

        manager.setCustomExternalPlayer(custom)
        manager.setExternalPlayer(.known(.vlc))
        manager.setExternalPlayer(nil)
        let reloaded = SettingsManager(userDefaults: defaults)

        #expect(reloaded.playback.externalPlayer == nil)
        #expect(reloaded.playback.customExternalPlayer == custom)
        reloaded.setExternalPlayer(.custom)
        #expect(reloaded.playback.resolvedExternalPlayer == .custom(custom))
    }

    @Test func `commercial auto skip is off unless chosen`() throws {
        #expect(try !decode(#"{"playback":{"autoSkipIntros":true}}"#).playback.autoSkipCommercials)
        #expect(try decode(#"{"playback":{"autoSkipCommercials":true}}"#).playback.autoSkipCommercials)
    }

    @Test func `double tap to seek is on unless turned off`() throws {
        #expect(try decode(#"{"playback":{"autoSkipIntros":true}}"#).playback.doubleTapToSeek)
        #expect(try !decode(#"{"playback":{"doubleTapToSeek":false}}"#).playback.doubleTapToSeek)
    }

    @Test func `subtitles on skip back are on unless turned off`() throws {
        #expect(try decode(#"{"playback":{"autoSkipIntros":true}}"#).playback.showSubtitlesOnSkipBack)
        #expect(try !decode(#"{"playback":{"showSubtitlesOnSkipBack":false}}"#).playback.showSubtitlesOnSkipBack)
    }

    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }
}
