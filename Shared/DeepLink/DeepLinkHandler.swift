import SwiftUI

/// What a platform's main view does for a link.
@MainActor
protocol DeepLinkNavigating: PlaybackPresenting {
    var isShowingPlayer: Bool { get }
    func closePlayerForDeepLink()
    func openDeepLinkTab(_ tab: DeepLink.Tab)
    func showDeepLinkMedia(_ media: MediaItem)
    func showDeepLinkLibrary(_ library: Library)
}

/// Acts on a link once its profile is active: finds its server, its media or channel, and opens or plays it.
@MainActor
struct DeepLinkHandler {
    enum Failure: Error, Equatable {
        case serverNotInProfile
        case serverUnavailable
        case notFound
        case channelNotFound

        var message: String {
            switch self {
            case .serverNotInProfile: String(localized: "deepLinks.serverNotInProfile")
            case .serverUnavailable: String(localized: "deepLinks.serverUnavailable")
            case .notFound: String(localized: "deepLinks.notFound")
            case .channelNotFound: String(localized: "deepLinks.channelNotFound")
            }
        }
    }

    /// A server that is reconnecting, e.g. after the device woke up, is waited for this long.
    static let serverWait: Duration = .seconds(20)

    let sessionManager: SessionManager
    let libraryStore: LibraryStore
    let exploreRegistry: ExploreSourceRegistry
    let router: DeepLinkRouter
    let navigator: any DeepLinkNavigating

    private var registry: ServerRegistry {
        sessionManager.registry
    }

    /// Nil when the link was handled, or abandoned for a reason that needs no message.
    func handle(_ link: DeepLink) async -> Failure? {
        switch link.destination {
        case .open:
            return nil
        case let .tab(tab):
            await closePlayer()
            navigator.openDeepLinkTab(tab)
            return nil
        case let .search(query):
            await closePlayer()
            navigator.openDeepLinkTab(.search)
            if let query {
                router.searchRequest = DeepLinkRouter.SearchRequest(query: query)
            }
            return nil
        case let .library(identity):
            switch await services(for: identity.server) {
            case let .failure(failure):
                return failure
            case .success:
                if libraryStore.library(identity) == nil {
                    try? await libraryStore.loadLibraries()
                }
                guard let library = libraryStore.library(identity) else { return .notFound }
                await closePlayer()
                navigator.showDeepLinkLibrary(library)
                return nil
            }
        case let .media(target):
            switch await resolve(target) {
            case let .failure(failure):
                return failure
            case let .success((media, _)):
                await closePlayer()
                navigator.showDeepLinkMedia(media)
                return nil
            }
        case let .play(target, mode, options):
            switch await resolve(target) {
            case let .failure(failure):
                return failure
            case let .success((media, services)):
                await closePlayer()
                await PlaybackLauncher(services: services, coordinator: navigator).play(
                    ratingKey: media.id,
                    type: media.type,
                    shuffle: mode == .shuffle,
                    shouldResumeFromOffset: mode != .restart,
                    startOptions: options,
                )
                return nil
            }
        case let .liveChannel(reference, server):
            return await tune(reference, server: server)
        }
    }

    // MARK: - Servers

    /// The services of a server of the profile, once it has connected.
    func services(for server: ServerIdentity) async -> Result<MediaServices, Failure> {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.serverWait
        while true {
            guard let session = registry.session(for: server), session.isEnabled else {
                return .failure(.serverNotInProfile)
            }
            // An unreachable server still opens: its cache and downloads answer.
            if session.status != .connecting, let services = registry.services(for: server) {
                return .success(services)
            }
            if session.status == .needsReauthentication || clock.now >= deadline || Task.isCancelled {
                return .failure(.serverUnavailable)
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    // MARK: - Media

    private func resolve(_ target: DeepLink.MediaTarget) async -> Result<(MediaItem, MediaServices), Failure> {
        switch target {
        case let .item(identity, _):
            let services: MediaServices
            switch await self.services(for: identity.server) {
            case let .failure(failure):
                return .failure(failure)
            case let .success(value):
                services = value
            }
            do {
                let media = try await services.detail.mediaItem(id: identity.itemID)
                return .success((media, services))
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return .failure(.serverUnavailable) }
                if error.isTransportFailure {
                    return .failure(.serverUnavailable)
                }
                ErrorReporter.capture(error)
                return .failure(.notFound)
            }
        case let .catalog(catalog):
            return await resolve(catalog)
        }
    }

    private func resolve(_ catalog: DeepLink.CatalogTarget) async -> Result<(MediaItem, MediaServices), Failure> {
        await waitForServers()
        guard var item = Self.exploreItem(for: catalog) else { return .failure(.notFound) }
        if catalog.title == nil {
            // Without a title the servers cannot be searched: Plex Discover names the title from its ids.
            guard let plex = exploreRegistry.source(.plex) as? PlexExploreSource,
                  let found = try? await plex.catalogItem(kind: item.kind, externalIDs: catalog.ids)
            else { return .failure(.notFound) }
            item = item.enriched(with: found)
        }
        let match = await exploreRegistry.matcher.match(item)
        guard let copy = Self.preferredCopy(match.copies) else {
            return .failure(match.isComplete ? .notFound : .serverUnavailable)
        }
        guard let services = registry.services(for: copy.server) else { return .failure(.serverUnavailable) }
        return .success((copy.media, services))
    }

    /// Catalog links search every server, so the ones still connecting are waited for.
    private func waitForServers() async {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.serverWait
        while registry.sessions.contains(where: { $0.isEnabled && $0.status == .connecting }),
              clock.now < deadline, !Task.isCancelled
        {
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    static func exploreItem(for catalog: DeepLink.CatalogTarget) -> ExploreItem? {
        guard !catalog.ids.isEmpty else { return nil }
        return ExploreItem(
            source: .plex,
            sourceID: "deeplink",
            kind: catalog.kind == .movie ? .movie : .show,
            title: catalog.title ?? "",
            originalTitle: nil,
            year: catalog.year,
            overview: nil,
            posterURL: nil,
            backdropURL: nil,
            externalIDs: catalog.ids,
            plexGuid: nil,
            seerrMedia: nil,
        )
    }

    /// The copy the viewer is furthest into, otherwise the best one: reachable first, then the order of
    /// `MediaCopy.sorted`.
    static func preferredCopy(_ copies: [MediaCopy]) -> MediaCopy? {
        let reachable = copies.filter(\.isReachable)
        let candidates = reachable.isEmpty ? copies : reachable
        if let started = candidates.filter({ ($0.media.viewOffset ?? 0) > 0 })
            .max(by: { ($0.media.viewOffset ?? 0) < ($1.media.viewOffset ?? 0) })
        {
            return started
        }
        return candidates.first
    }

    // MARK: - Live TV

    private func tune(_ reference: String, server: ServerIdentity?) async -> Failure? {
        var candidates: [MediaServices]
        if let server {
            switch await services(for: server) {
            case let .failure(failure):
                return failure
            case let .success(services):
                candidates = [services]
            }
        } else {
            await waitForServers()
            if registry.liveTVServices.isEmpty {
                await registry.refreshLiveTVAvailability()
            }
            candidates = registry.liveTVServices
        }
        for services in candidates {
            guard let channels = try? await services.liveTV.channels(),
                  let index = Self.channelIndex(matching: reference, in: channels)
            else { continue }
            await closePlayer()
            navigator.showLivePlayer(
                context: LiveTVLaunchContext(channels: channels, selectedIndex: index),
                services: services,
            )
            return nil
        }
        return .channelNotFound
    }

    /// Matched on the channel id, then its number (`2` finds `002`), call sign and title, ignoring case, so a link can
    /// be written by hand (`strimr://live/TF1`).
    static func channelIndex(matching reference: String, in channels: [LiveTVChannel]) -> Int? {
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        func same(_ value: String?) -> Bool {
            guard let value else { return false }
            return value.compare(reference, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        let number = LiveTVChannelNumber(reference)
        return channels.firstIndex { $0.providerID == reference }
            ?? channels.firstIndex { same($0.number) }
            ?? number
            .flatMap { number in channels.firstIndex { $0.number.flatMap(LiveTVChannelNumber.init) == number } }
            ?? channels.firstIndex { same($0.callSign) }
            ?? channels.firstIndex { same($0.title) }
    }

    // MARK: - Player

    /// A link replaces what is playing, or the page it opens would stay hidden under the player.
    private func closePlayer() async {
        guard navigator.isShowingPlayer else { return }
        navigator.closePlayerForDeepLink()
        // Lets the dismissal finish before the next presentation.
        try? await Task.sleep(for: .milliseconds(600))
    }
}

extension View {
    /// Handles the pending link once its profile is active. Installed on each platform's main view.
    func handlesDeepLinks(navigator: any DeepLinkNavigating) -> some View {
        modifier(DeepLinkHandlingModifier(navigator: navigator))
    }
}

private struct DeepLinkHandlingModifier: ViewModifier {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(ExploreSourceRegistry.self) private var exploreRegistry
    @Environment(DeepLinkRouter.self) private var router
    @Environment(ToastCenter.self) private var toastCenter: ToastCenter?
    @Environment(\.scenePhase) private var scenePhase

    let navigator: any DeepLinkNavigating

    private struct Key: Equatable {
        let link: DeepLink?
        let isActive: Bool
    }

    func body(content: Content) -> some View {
        // A quick action or Handoff can launch the app before its scene is active, when a player cannot be presented.
        content
            .task(id: Key(link: router.pending, isActive: scenePhase == .active)) {
                guard scenePhase == .active, let link = router.pending, link.profile == nil else { return }
                #if DEBUG
                    if DemoMode.isEnabled {
                        router.clear(link)
                        return
                    }
                #endif
                let handler = DeepLinkHandler(
                    sessionManager: sessionManager,
                    libraryStore: libraryStore,
                    exploreRegistry: exploreRegistry,
                    router: router,
                    navigator: navigator,
                )
                let failure = await handler.handle(link)
                // A run cancelled when the scene turned active or the link changed is taken over by the next one.
                guard !Task.isCancelled else { return }
                router.clear(link)
                guard let failure else { return }
                toastCenter?.show(Toast(style: .failure, title: failure.message))
            }
    }
}
