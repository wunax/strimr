import AppIntents
import Foundation

/// Every intent opens the app and hands a link to `DeepLinkRouter`, so Siri, Shortcuts and Spotlight go through the
/// same path as a `strimr://` URL.
@MainActor
private func open(_ link: DeepLink?) {
    guard let link else { return }
    DeepLinkRouter.shared.receive(link)
}

struct OpenMediaIntent: OpenIntent {
    static let title = LocalizedStringResource("intents.openMedia.title")
    static let description = IntentDescription(LocalizedStringResource("intents.openMedia.description"))

    @Parameter(title: LocalizedStringResource("intents.media.parameter"))
    var target: MediaEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        open(target.link { .media($0) })
        return .result()
    }
}

struct PlayMediaIntent: AppIntent {
    static let title = LocalizedStringResource("intents.play.title")
    static let description = IntentDescription(LocalizedStringResource("intents.play.description"))
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("intents.media.parameter"))
    var media: MediaEntity

    @Parameter(title: LocalizedStringResource("intents.play.fromStart"), default: false)
    var fromStart: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("intents.play.summary \(\.$media)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        open(media.link { .play($0, mode: fromStart ? .restart : .resume) })
        return .result()
    }
}

struct ContinueWatchingIntent: AppIntent {
    static let title = LocalizedStringResource("intents.continueWatching.title")
    static let description = IntentDescription(LocalizedStringResource("intents.continueWatching.description"))
    static let openAppWhenRun = true

    /// The app may still be launching: its Continue Watching row is waited for.
    @MainActor
    func perform() async throws -> some IntentResult {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while AppEntryPoints.shared.snapshot?.resume == nil, clock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
        if let resume = AppEntryPoints.shared.snapshot?.resume {
            open(DeepLink(.play(.item(resume.identity, kind: resume.type), mode: .resume)))
        } else {
            open(DeepLink(.tab(.home)))
        }
        return .result()
    }
}

struct ShuffleShowIntent: AppIntent {
    static let title = LocalizedStringResource("intents.shuffle.title")
    static let description = IntentDescription(LocalizedStringResource("intents.shuffle.description"))
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("intents.shuffle.parameter"))
    var show: MediaEntity

    static var parameterSummary: some ParameterSummary {
        Summary("intents.shuffle.summary \(\.$show)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        open(show.link { .play($0, mode: .shuffle) })
        return .result()
    }
}

struct PlayLiveChannelIntent: AppIntent {
    static let title = LocalizedStringResource("intents.liveChannel.title")
    static let description = IntentDescription(LocalizedStringResource("intents.liveChannel.description"))
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("intents.channel.parameter"))
    var channel: LiveChannelEntity

    static var parameterSummary: some ParameterSummary {
        Summary("intents.liveChannel.summary \(\.$channel)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        open(channel.link)
        return .result()
    }
}

struct SearchMediaIntent: ShowInAppSearchResultsIntent {
    static let title = LocalizedStringResource("intents.search.title")
    static let description = IntentDescription(LocalizedStringResource("intents.search.description"))
    static let searchScopes: [StringSearchScope] = [.general]

    @Parameter(title: LocalizedStringResource("intents.search.parameter"))
    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        open(DeepLink(.search(criteria.term)))
        return .result()
    }
}

struct StrimrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueWatchingIntent(),
            phrases: [
                "Resume in \(.applicationName)",
                "Continue watching in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intents.continueWatching.shortTitle"),
            systemImageName: "play.circle",
        )
        AppShortcut(
            intent: PlayMediaIntent(),
            phrases: [
                "Play \(\.$media) in \(.applicationName)",
                "Watch \(\.$media) in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intents.play.shortTitle"),
            systemImageName: "play.fill",
        )
        AppShortcut(
            intent: ShuffleShowIntent(),
            phrases: [
                "Shuffle \(\.$show) in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intents.shuffle.shortTitle"),
            systemImageName: "shuffle",
        )
        AppShortcut(
            intent: PlayLiveChannelIntent(),
            phrases: [
                "Watch \(\.$channel) live in \(.applicationName)",
                "Tune to \(\.$channel) in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intents.liveChannel.shortTitle"),
            systemImageName: "tv",
        )
        AppShortcut(
            intent: SearchMediaIntent(),
            phrases: [
                "Search in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intents.search.shortTitle"),
            systemImageName: "magnifyingglass",
        )
    }
}
