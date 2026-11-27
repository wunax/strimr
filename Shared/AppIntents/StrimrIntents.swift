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

struct OpenLibraryIntent: OpenIntent {
    static let title = LocalizedStringResource("intents.openLibrary.title")
    static let description = IntentDescription(LocalizedStringResource("intents.openLibrary.description"))

    @Parameter(title: LocalizedStringResource("intents.library.parameter"))
    var target: LibraryEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        open(target.link)
        return .result()
    }
}

enum WatchState: String, AppEnum {
    case watched
    case unwatched

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intents.watchState.type"),
    )
    static let caseDisplayRepresentations: [WatchState: DisplayRepresentation] = [
        .watched: DisplayRepresentation(title: LocalizedStringResource("intents.watchState.watched")),
        .unwatched: DisplayRepresentation(title: LocalizedStringResource("intents.watchState.unwatched")),
    ]
}

/// The only intent that changes the server, so it asks first. It runs without opening the app: links never change
/// the watch state, since any web page can open them, but an intent only runs from Siri or Shortcuts.
struct SetWatchStateIntent: AppIntent {
    static let title = LocalizedStringResource("intents.watchState.title")
    static let description = IntentDescription(LocalizedStringResource("intents.watchState.description"))

    @Parameter(title: LocalizedStringResource("intents.media.parameter"))
    var media: MediaEntity

    @Parameter(title: LocalizedStringResource("intents.watchState.parameter"), default: .watched)
    var state: WatchState

    static var parameterSummary: some ParameterSummary {
        Summary("intents.watchState.summary \(\.$media) \(\.$state)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let watched = state == .watched
        let title = media.title
        try await requestConfirmation(
            actionName: .set,
            dialog: watched
                ? IntentDialog("intents.watchState.confirm.watched \(title)")
                : IntentDialog("intents.watchState.confirm.unwatched \(title)"),
        )
        guard let identity = media.identity,
              let services = await AppIntentsEnvironment.readyServices(for: identity.server)
        else { throw StrimrIntentError.sessionUnavailable }
        let item: MediaItem
        do {
            item = try await services.detail.mediaItem(id: identity.itemID)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { throw error }
            ErrorReporter.capture(error)
            throw StrimrIntentError.failed(error.localizedDescription)
        }
        if case let .failed(message) = await MediaQuickActions(services: services).setPlayed(watched, for: item) {
            throw StrimrIntentError.failed(message)
        }
        return .result(dialog: watched
            ? IntentDialog("intents.watchState.done.watched \(title)")
            : IntentDialog("intents.watchState.done.unwatched \(title)"))
    }
}

enum StrimrIntentError: Error, CustomLocalizedStringResourceConvertible {
    case sessionUnavailable
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .sessionUnavailable: "intents.error.sessionUnavailable"
        case let .failed(message): "\(message)"
        }
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
            intent: SetWatchStateIntent(),
            phrases: [
                "Mark \(\.$media) as watched in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intents.watchState.shortTitle"),
            systemImageName: "checkmark.circle",
        )
        AppShortcut(
            intent: OpenLibraryIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intents.openLibrary.shortTitle"),
            systemImageName: "rectangle.stack",
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
