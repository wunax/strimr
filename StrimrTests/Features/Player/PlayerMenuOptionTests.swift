import Foundation
@testable import Strimr
import Testing

struct PlayerMenuOptionTests {
    @Test func `the selected subtitle track is checked and off comes last`() {
        let sections = PlayerMenus.subtitles(subtitles(selectedTrackID: 2))
        let options = sections[0].options

        #expect(options.map(\.id) == ["track.1", "track.2", "off"])
        #expect(options.map(\.isSelected) == [false, true, false])
    }

    @Test func `subtitles off is checked without a selected track`() {
        let options = PlayerMenus.subtitles(subtitles(selectedTrackID: nil))[0].options

        #expect(options.last?.isSelected == true)
    }

    @Test func `subtitle search only shows when available`() {
        let without = PlayerMenus.subtitles(subtitles(canSearch: false))
        let with = PlayerMenus.subtitles(subtitles(canSearch: true))

        #expect(without.option(id: "search") == nil)
        #expect(with.option(id: "search") != nil)
    }

    @Test func `audio shaping options are disabled when unavailable`() {
        var input = audio()
        input.isAudioShapingAvailable = false
        let sections = PlayerMenus.audio(input)

        #expect(sections.option(id: "nightMode")?.isDisabled == true)
        #expect(sections.option(id: "dialogueBoost")?.isDisabled == true)
    }

    @Test func `dialogue boost lists every level with the current one checked`() {
        var input = audio()
        input.dialogueBoost = .strong
        let levels = PlayerMenus.audio(input).option(id: "dialogueBoost")?.submenuSections?.first?.options ?? []

        #expect(levels.count == DialogueBoost.allCases.count)
        #expect(levels.filter(\.isSelected).map(\.id) == ["dialogueBoost.\(DialogueBoost.strong.rawValue)"])
    }

    @Test func `a single version hides the version menu`() {
        let sections = PlayerMenus.more(more())

        #expect(sections.option(id: "version") == nil)
    }

    @Test func `several versions show the version menu`() {
        var input = more()
        input.versions = [
            PlaybackSettingsVersion(id: "a", title: "4K", subtitle: "", isAvailable: true, isSelected: true),
            PlaybackSettingsVersion(id: "b", title: "1080p", subtitle: "", isAvailable: true, isSelected: false),
        ]
        let version = PlayerMenus.more(input).option(id: "version")

        #expect(version?.subtitle == "4K")
        #expect(version?.submenuSections?.first?.options.count == 2)
    }

    @Test func `live TV has no speed or quality but switches channels`() {
        var input = more()
        input.isLive = true
        input.canSwitchNextChannel = true
        let sections = PlayerMenus.more(input)

        #expect(sections.option(id: "speed") == nil)
        #expect(sections.option(id: "quality") == nil)
        #expect(sections.option(id: "previousChannel")?.isDisabled == true)
        #expect(sections.option(id: "nextChannel")?.isDisabled == false)
    }

    @Test func `SharePlay has no sleep timer`() {
        var input = more()
        input.isSharePlay = true

        #expect(PlayerMenus.more(input).option(id: "sleepTimer") == nil)
        #expect(PlayerMenus.more(more()).option(id: "sleepTimer") != nil)
    }

    @Test func `the current speed is checked`() {
        var input = more()
        input.playbackRate = 1.5
        let speeds = PlayerMenus.more(input).option(id: "speed")?.submenuSections?.first?.options ?? []

        #expect(speeds.filter(\.isSelected).count == 1)
        #expect(speeds.first(where: \.isSelected)?.id == "speed.\(PlaybackSpeedOption(rate: 1.5).valueText)")
    }

    @Test func `fill only shows when it differs from the fitted picture`() {
        var input = more()
        input.fillScale = 1
        let fitted = PlayerMenus.more(input).option(id: "display")?.submenuSections?.first?.options ?? []
        input.fillScale = 1.3
        let wide = PlayerMenus.more(input).option(id: "display")?.submenuSections?.first?.options ?? []

        #expect(fitted.map(\.id) == ["display.fit", "display.zoom"])
        #expect(wide.map(\.id) == ["display.fit", "display.fill", "display.zoom"])
    }

    @Test func `a menu opens on its checked choice`() {
        let sections = PlayerMenus.subtitles(subtitles(selectedTrackID: 2))

        #expect(sections.initialFocusOption?.id == "track.2")
    }

    @Test func `a switched-on toggle does not take the initial focus`() {
        var input = more()
        input.showsStatistics = true
        let sections = PlayerMenus.more(input)

        #expect(sections.initialFocusOption?.id == "speed")
    }

    private func subtitles(selectedTrackID: Int? = nil, canSearch: Bool = false) -> PlayerMenus.Subtitles {
        PlayerMenus.Subtitles(
            tracks: [track(id: 1), track(id: 2)],
            selectedTrackID: selectedTrackID,
            canSearch: canSearch,
            canResetTrackSelections: false,
            sync: nil,
            appearance: nil,
        )
    }

    private func audio() -> PlayerMenus.Audio {
        PlayerMenus.Audio(
            tracks: [track(id: 1, type: .audio)],
            selectedTrackID: 1,
            nightMode: false,
            dialogueBoost: .off,
            isAudioShapingAvailable: true,
            sync: nil,
        )
    }

    private func more() -> PlayerMenus.More {
        PlayerMenus.More(
            isLive: false,
            playbackRate: 1,
            quality: .original,
            versions: [],
            zoom: .fit,
            fillScale: 1,
            sleepTimerMode: nil,
            sleepTimerDeadline: nil,
            sleepTimerModes: [],
            mediaKind: .movie,
            isSharePlay: false,
            showsStatistics: false,
        )
    }

    private func track(id: Int, type: PlayerTrack.TrackType = .subtitle) -> PlaybackSettingsTrack {
        PlaybackSettingsTrack(
            track: PlayerTrack(
                id: id,
                ffIndex: id,
                providerStreamID: id,
                type: type,
                title: "Track \(id)",
                language: "eng",
                codec: "srt",
                isDefault: false,
                isForced: false,
                isHearingImpaired: false,
                isCommentary: false,
                isExternal: false,
                isSelected: false,
            ),
            metadata: nil,
        )
    }
}
