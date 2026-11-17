import Foundation

/// Player settings described independently of how they are drawn, for the anchored menus of the tvOS system style.
/// The classic style keeps its own panel views.
struct PlayerMenuSection: Identifiable {
    var id: String
    var title: String?
    var options: [PlayerMenuOption]
}

struct PlayerMenuOption: Identifiable {
    enum Kind {
        /// One of several exclusive options; picking it closes the menu.
        case choice(isSelected: Bool)
        /// Switched on and off in place, the menu stays open.
        case toggle(isOn: Bool)
        case submenu([PlayerMenuSection])
        /// Opens an adjustment bar or a panel.
        case action
    }

    var id: String
    var title: String
    var subtitle: String?
    var systemImage: String?
    var isDisabled = false
    var kind: Kind
    var perform: () -> Void = {}

    var isSelected: Bool {
        switch kind {
        case let .choice(isSelected): isSelected
        case let .toggle(isOn): isOn
        case .submenu, .action: false
        }
    }

    var submenuSections: [PlayerMenuSection]? {
        if case let .submenu(sections) = kind {
            return sections
        }
        return nil
    }
}

extension [PlayerMenuSection] {
    func option(id: String) -> PlayerMenuOption? {
        for section in self {
            for option in section.options {
                if option.id == id {
                    return option
                }
                if let match = option.submenuSections?.option(id: id) {
                    return match
                }
            }
        }
        return nil
    }

    /// The menu opens on its checked choice, or on its first row. A switched-on toggle is checked too, but landing on
    /// it would let one stray click turn it off.
    var initialFocusOption: PlayerMenuOption? {
        let options = flatMap(\.options).filter { !$0.isDisabled }
        let checkedChoice = options.first { option in
            if case .choice(isSelected: true) = option.kind {
                return true
            }
            return false
        }
        return checkedChoice ?? options.first
    }
}

enum PlayerMenus {
    struct Subtitles {
        var tracks: [PlaybackSettingsTrack]
        var selectedTrackID: Int?
        var canSearch: Bool
        var canResetTrackSelections: Bool
        var sync: PlaybackOffsetMenuItem?
        var appearance: SubtitleAppearanceAvailability?
        var onSelect: (Int?) -> Void = { _ in }
        var onSearch: () -> Void = {}
        var onResetTrackSelections: () -> Void = {}
        var onSync: (PlaybackOffsetKind) -> Void = { _ in }
        var onAppearance: () -> Void = {}
    }

    struct Audio {
        var tracks: [PlaybackSettingsTrack]
        var selectedTrackID: Int?
        var nightMode: Bool
        var dialogueBoost: DialogueBoost
        var isAudioShapingAvailable: Bool
        var sync: PlaybackOffsetMenuItem?
        var onSelect: (Int?) -> Void = { _ in }
        var onToggleNightMode: () -> Void = {}
        var onSelectDialogueBoost: (DialogueBoost) -> Void = { _ in }
        var onSync: (PlaybackOffsetKind) -> Void = { _ in }
    }

    struct More {
        var isLive: Bool
        var playbackRate: Float
        var quality: TranscodeQualityPreset
        /// Empty when the item has a single version.
        var versions: [PlaybackSettingsVersion]
        var zoom: VideoZoom
        var fillScale: Double
        var sleepTimerMode: SleepTimerMode?
        var sleepTimerDeadline: Date?
        var sleepTimerModes: [SleepTimerMode]
        var mediaKind: MediaKind?
        var isSharePlay: Bool
        var showsStatistics: Bool
        var canSwitchPreviousChannel = false
        var canSwitchNextChannel = false
        var onSelectRate: (Float) -> Void = { _ in }
        var onSelectQuality: (TranscodeQualityPreset) -> Void = { _ in }
        var onSelectVersion: (String) -> Void = { _ in }
        var onSelectZoom: (VideoZoom) -> Void = { _ in }
        var onCustomZoom: () -> Void = {}
        var onSelectSleepTimer: (SleepTimerMode?) -> Void = { _ in }
        var onExtendSleepTimer: () -> Void = {}
        var onToggleStatistics: () -> Void = {}
        var onPreviousChannel: () -> Void = {}
        var onNextChannel: () -> Void = {}
    }

    static func subtitles(_ input: Subtitles) -> [PlayerMenuSection] {
        var tracks = input.tracks.map { track in
            PlayerMenuOption(
                id: "track.\(track.id)",
                title: track.title,
                subtitle: track.subtitle,
                kind: .choice(isSelected: input.selectedTrackID == track.id),
                perform: { input.onSelect(track.id) },
            )
        }
        tracks.append(PlayerMenuOption(
            id: "off",
            title: String(localized: "player.settings.subtitles.off"),
            kind: .choice(isSelected: input.selectedTrackID == nil),
            perform: { input.onSelect(nil) },
        ))

        var more: [PlayerMenuOption] = []
        if input.canSearch {
            more.append(PlayerMenuOption(
                id: "search",
                title: String(localized: "subtitles.search.action"),
                systemImage: "magnifyingglass",
                kind: .action,
                perform: input.onSearch,
            ))
        }
        if input.canResetTrackSelections {
            more.append(PlayerMenuOption(
                id: "reset",
                title: String(localized: "player.settings.tracks.reset"),
                systemImage: "arrow.counterclockwise",
                kind: .action,
                perform: input.onResetTrackSelections,
            ))
        }
        if let sync = input.sync {
            more.append(syncOption(sync, perform: input.onSync))
        }
        if let appearance = input.appearance {
            more.append(PlayerMenuOption(
                id: "appearance",
                title: String(localized: "player.settings.subtitles.appearance"),
                subtitle: appearance.message,
                systemImage: "textformat.size",
                isDisabled: !appearance.isAvailable,
                kind: .action,
                perform: input.onAppearance,
            ))
        }

        return sections([
            PlayerMenuSection(id: "tracks", title: String(localized: "player.settings.subtitles"), options: tracks),
            PlayerMenuSection(id: "more", options: more),
        ])
    }

    static func audio(_ input: Audio) -> [PlayerMenuSection] {
        let tracks = input.tracks.isEmpty
            ? [PlayerMenuOption(
                id: "empty",
                title: String(localized: "player.settings.audio.empty"),
                isDisabled: true,
                kind: .action,
            )]
            : input.tracks.map { track in
                PlayerMenuOption(
                    id: "track.\(track.id)",
                    title: track.title,
                    subtitle: track.subtitle,
                    kind: .choice(isSelected: input.selectedTrackID == track.id),
                    perform: { input.onSelect(track.id) },
                )
            }

        let unavailable = input.isAudioShapingAvailable
            ? nil
            : String(localized: "player.settings.audioEnhancements.unavailable")
        var adjustments = [
            PlayerMenuOption(
                id: "nightMode",
                title: String(localized: "settings.playback.nightMode"),
                subtitle: unavailable,
                systemImage: "moon.stars",
                isDisabled: !input.isAudioShapingAvailable,
                kind: .toggle(isOn: input.nightMode),
                perform: input.onToggleNightMode,
            ),
            PlayerMenuOption(
                id: "dialogueBoost",
                title: String(localized: "settings.playback.dialogueBoost"),
                subtitle: unavailable ?? input.dialogueBoost.title,
                systemImage: "person.wave.2",
                isDisabled: !input.isAudioShapingAvailable,
                kind: .submenu([PlayerMenuSection(
                    id: "dialogueBoost",
                    options: DialogueBoost.allCases.map { boost in
                        PlayerMenuOption(
                            id: "dialogueBoost.\(boost.rawValue)",
                            title: boost.title,
                            kind: .choice(isSelected: boost == input.dialogueBoost),
                            perform: { input.onSelectDialogueBoost(boost) },
                        )
                    },
                )]),
            ),
        ]
        if let sync = input.sync {
            adjustments.append(syncOption(sync, perform: input.onSync))
        }

        return sections([
            PlayerMenuSection(id: "tracks", title: String(localized: "player.settings.audio"), options: tracks),
            PlayerMenuSection(
                id: "adjustments",
                title: String(localized: "settings.playback.audioEnhancements"),
                options: adjustments,
            ),
        ])
    }

    static func more(_ input: More) -> [PlayerMenuSection] {
        var playback: [PlayerMenuOption] = []
        if !input.isLive {
            playback.append(speedOption(input))
            playback.append(qualityOption(input))
        }
        if !input.versions.isEmpty {
            playback.append(versionOption(input))
        }
        playback.append(displayOption(input))
        if !input.isSharePlay {
            playback.append(sleepTimerOption(input))
        }
        playback.append(PlayerMenuOption(
            id: "statistics",
            title: String(localized: "player.statistics.title"),
            systemImage: "chart.bar.xaxis",
            kind: .toggle(isOn: input.showsStatistics),
            perform: input.onToggleStatistics,
        ))

        var channels: [PlayerMenuOption] = []
        if input.isLive {
            channels = [
                PlayerMenuOption(
                    id: "previousChannel",
                    title: String(localized: "livetv.player.previousChannel"),
                    systemImage: "chevron.up",
                    isDisabled: !input.canSwitchPreviousChannel,
                    kind: .action,
                    perform: input.onPreviousChannel,
                ),
                PlayerMenuOption(
                    id: "nextChannel",
                    title: String(localized: "livetv.player.nextChannel"),
                    systemImage: "chevron.down",
                    isDisabled: !input.canSwitchNextChannel,
                    kind: .action,
                    perform: input.onNextChannel,
                ),
            ]
        }

        return sections([
            PlayerMenuSection(id: "channels", options: channels),
            PlayerMenuSection(id: "playback", options: playback),
        ])
    }

    private static func sections(_ sections: [PlayerMenuSection]) -> [PlayerMenuSection] {
        sections.filter { !$0.options.isEmpty }
    }

    private static func syncOption(
        _ item: PlaybackOffsetMenuItem,
        perform: @escaping (PlaybackOffsetKind) -> Void,
    ) -> PlayerMenuOption {
        PlayerMenuOption(
            id: "sync",
            title: item.kind.title,
            subtitle: item.availability.message ?? item.value,
            systemImage: item.kind.systemImage,
            isDisabled: !item.availability.isAvailable,
            kind: .action,
            perform: { perform(item.kind) },
        )
    }

    private static func speedOption(_ input: More) -> PlayerMenuOption {
        let options = PlaybackSpeedOptions.all.map { option in
            PlayerMenuOption(
                id: "speed.\(option.valueText)",
                title: String(localized: "player.settings.speed.value \(option.valueText)"),
                kind: .choice(isSelected: abs(input.playbackRate - option.rate) < 0.001),
                perform: { input.onSelectRate(option.rate) },
            )
        }
        return PlayerMenuOption(
            id: "speed",
            title: String(localized: "player.settings.speed"),
            subtitle: String(
                localized: "player.settings.speed.value \(PlaybackSpeedOption(rate: input.playbackRate).valueText)",
            ),
            systemImage: "speedometer",
            kind: .submenu([PlayerMenuSection(id: "speed", options: options)]),
        )
    }

    private static func qualityOption(_ input: More) -> PlayerMenuOption {
        PlayerMenuOption(
            id: "quality",
            title: String(localized: "player.settings.quality"),
            subtitle: input.quality.title,
            systemImage: "slider.horizontal.3",
            kind: .submenu([PlayerMenuSection(
                id: "quality",
                options: TranscodeQualityPreset.displayOrder.map { preset in
                    PlayerMenuOption(
                        id: "quality.\(preset.rawValue)",
                        title: preset.title,
                        kind: .choice(isSelected: preset == input.quality),
                        perform: { input.onSelectQuality(preset) },
                    )
                },
            )]),
        )
    }

    private static func versionOption(_ input: More) -> PlayerMenuOption {
        PlayerMenuOption(
            id: "version",
            title: String(localized: "player.settings.version"),
            subtitle: input.versions.first(where: \.isSelected)?.title,
            systemImage: "film.stack",
            kind: .submenu([PlayerMenuSection(
                id: "version",
                options: input.versions.map { version in
                    PlayerMenuOption(
                        id: "version.\(version.id)",
                        title: version.title,
                        subtitle: version.subtitle,
                        isDisabled: !version.isAvailable,
                        kind: .choice(isSelected: version.isSelected),
                        perform: { input.onSelectVersion(version.id) },
                    )
                },
            )]),
        )
    }

    private static func displayOption(_ input: More) -> PlayerMenuOption {
        // Fill only differs from the fitted picture when the video and screen shapes differ.
        let showsFill = input.fillScale > 1.01
        var modes: [PlayerVideoScaleMode] = [.fit]
        if showsFill {
            modes.append(.fill)
        }
        var options = modes.map { mode in
            PlayerMenuOption(
                id: "display.\(mode.rawValue)",
                title: mode.feedbackTitle,
                kind: .choice(
                    isSelected: input.zoom.persistedMode == mode || (mode == .fit && input.zoom == .fill && !showsFill),
                ),
                perform: { input.onSelectZoom(VideoZoom(mode)) },
            )
        }
        options.append(PlayerMenuOption(
            id: "display.zoom",
            title: String(localized: "player.settings.display.zoom"),
            subtitle: input.zoom.persistedMode == nil ? input.zoom.feedbackTitle(fillScale: input.fillScale) : nil,
            kind: .action,
            perform: input.onCustomZoom,
        ))
        return PlayerMenuOption(
            id: "display",
            title: String(localized: "player.settings.display"),
            subtitle: input.zoom.feedbackTitle(fillScale: input.fillScale),
            systemImage: "arrow.up.left.and.arrow.down.right",
            kind: .submenu([PlayerMenuSection(id: "display", options: options)]),
        )
    }

    private static func sleepTimerOption(_ input: More) -> PlayerMenuOption {
        var options = [PlayerMenuOption(
            id: "sleepTimer.off",
            title: String(localized: "player.sleepTimer.off"),
            kind: .choice(isSelected: input.sleepTimerMode == nil),
            perform: { input.onSelectSleepTimer(nil) },
        )]
        if let deadline = input.sleepTimerDeadline {
            options.append(PlayerMenuOption(
                id: "sleepTimer.extend",
                title: String(localized: "player.sleepTimer.extend \(SleepTimer.extensionMinutes)"),
                subtitle: endsAt(deadline),
                systemImage: "plus",
                kind: .action,
                perform: input.onExtendSleepTimer,
            ))
        }
        options += input.sleepTimerModes.map { mode in
            PlayerMenuOption(
                id: "sleepTimer.\(mode)",
                title: mode.title(for: input.mediaKind),
                kind: .choice(isSelected: input.sleepTimerMode == mode),
                perform: { input.onSelectSleepTimer(mode) },
            )
        }

        let subtitle = input.sleepTimerDeadline.map(endsAt)
            ?? input.sleepTimerMode?.title(for: input.mediaKind)
            ?? String(localized: "player.sleepTimer.off")
        return PlayerMenuOption(
            id: "sleepTimer",
            title: String(localized: "player.sleepTimer.title"),
            subtitle: subtitle,
            systemImage: input.sleepTimerMode == nil ? "moon.zzz" : "moon.zzz.fill",
            kind: .submenu([PlayerMenuSection(id: "sleepTimer", options: options)]),
        )
    }

    private static func endsAt(_ deadline: Date) -> String {
        String(localized: "player.sleepTimer.endsAt \(deadline.formatted(date: .omitted, time: .shortened))")
    }
}
