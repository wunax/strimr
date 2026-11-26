import Foundation
import Observation

/// The active profile's connected Explore sources, and the one the tab shows.
@MainActor
@Observable
final class ExploreSourceRegistry {
    private(set) var sources: [any ExploreSource] = []
    private var preferredSourceID: ExploreSourceID?

    @ObservationIgnored let matcher: ExploreLibraryMatcher
    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let seerrStore: SeerrStore
    @ObservationIgnored private let trackers: TrackerCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isDisabled: Bool
    @ObservationIgnored private var builtKeys: [ExploreSourceID: String] = [:]
    @ObservationIgnored private var loadedProfileID: String?
    @ObservationIgnored private var candidates: [String: [ExploreSourceID: ExploreWatchlistTarget]] = [:]

    init(
        sessionManager: SessionManager,
        settingsManager: SettingsManager,
        seerrStore: SeerrStore,
        trackers: TrackerCoordinator? = nil,
        defaults: UserDefaults = .standard,
    ) {
        self.sessionManager = sessionManager
        self.seerrStore = seerrStore
        self.trackers = trackers ?? .shared
        self.defaults = defaults
        matcher = ExploreLibraryMatcher(sessionManager: sessionManager, settingsManager: settingsManager)
        #if DEBUG
            isDisabled = DemoMode.isEnabled
        #else
            isDisabled = false
        #endif
    }

    var hasSources: Bool {
        !sources.isEmpty
    }

    var activeSource: (any ExploreSource)? {
        let id = Self.resolveActive(preferred: preferredSourceID, connected: sources.map(\.id))
        return sources.first { $0.id == id }
    }

    var watchlistSources: [any ExploreSource] {
        sources.filter { $0.watchlist != nil }
    }

    func source(_ id: ExploreSourceID) -> (any ExploreSource)? {
        sources.first { $0.id == id }
    }

    /// The user's pick while it is connected, then the first connected source in priority order.
    static func resolveActive(preferred: ExploreSourceID?, connected: [ExploreSourceID]) -> ExploreSourceID? {
        if let preferred, connected.contains(preferred) {
            return preferred
        }
        return ExploreSourceID.allCases.first(where: connected.contains)
    }

    func select(_ id: ExploreSourceID) {
        preferredSourceID = id
        guard let profileID else { return }
        defaults.set(id.rawValue, forKey: Self.preferenceKey(profileID: profileID))
    }

    static func preferenceKey(profileID: String) -> String {
        "strimr.explore.activeSource.\(profileID)"
    }

    // MARK: - Sources

    private var profileID: String? {
        sessionManager.activeProfile?.id
    }

    /// What the sources are built from. A change rebuilds the sources it concerns.
    var configurationKey: String {
        [
            profileID ?? "-",
            String(sessionManager.registry.generation),
            seerrStore.isLoggedIn ? seerrStore.baseURLString ?? "-" : "-",
            sessionManager.registry.plexWatchlistAccountID ?? "-",
            trackers.state(for: .trakt).isConnected ? "trakt" : "-",
            trackers.state(for: .simkl).isConnected ? "simkl" : "-",
        ].joined(separator: "|")
    }

    func sync() async {
        guard !isDisabled else { return }
        if loadedProfileID != profileID {
            loadedProfileID = profileID
            preferredSourceID = profileID
                .flatMap { defaults.string(forKey: Self.preferenceKey(profileID: $0)) }
                .flatMap(ExploreSourceID.init(rawValue:))
            builtKeys = [:]
            candidates = [:]
            matcher.reset()
        }

        var next: [ExploreSourceID: any ExploreSource] = [:]
        for id in ExploreSourceID.allCases {
            let key = sourceKey(id)
            if let key, builtKeys[id] == key, let existing = source(id) {
                next[id] = existing
            } else if let key, let built = await build(id) {
                guard !Task.isCancelled else { return }
                next[id] = built
                builtKeys[id] = key
            } else {
                builtKeys[id] = nil
            }
        }
        let rebuilt = ExploreSourceID.allCases.compactMap { next[$0] }
        if rebuilt.map(ObjectIdentifier.init) != sources.map(ObjectIdentifier.init) {
            candidates = [:]
        }
        sources = rebuilt
    }

    private func sourceKey(_ id: ExploreSourceID) -> String? {
        let profile = profileID ?? "-"
        switch id {
        case .seerr:
            guard seerrStore.isLoggedIn, let baseURL = seerrStore.baseURLString else { return nil }
            return "\(profile)|\(baseURL)"
        case .plex:
            return sessionManager.registry.plexWatchlistAccountID.map { "\(profile)|\($0)" }
        case .trakt:
            return trackers.state(for: .trakt).isConnected ? profile : nil
        case .simkl:
            return trackers.state(for: .simkl).isConnected ? profile : nil
        }
    }

    private func build(_ id: ExploreSourceID) async -> (any ExploreSource)? {
        switch id {
        case .seerr:
            return seerrStore.baseURLString.flatMap(URL.init(string:)).map { SeerrExploreSource(baseURL: $0) }
        case .plex:
            guard let context = await sessionManager.registry.plexDiscoverContext() else { return nil }
            return try? PlexExploreSource(context: context)
        case .trakt:
            return (trackers.catalogClient(for: .trakt) as? TraktClient).map(TraktExploreSource.init)
        case .simkl:
            return (trackers.catalogClient(for: .simkl) as? SimklClient).map(SimklExploreSource.init)
        }
    }

    // MARK: - Watchlists of server items

    /// Every connected watchlist that can hold the item. A source that fails is left out of this answer and asked again
    /// next time.
    func watchlistOptions(for media: MediaItem, services: MediaServices) async -> [ExploreWatchlistOption] {
        guard let kind = ExploreItemKind(mediaKind: media.type) else { return [] }
        let sources = watchlistSources
        guard !sources.isEmpty else { return [] }
        let cacheKey = "\(media.identity.server.stableKey)|\(media.id)"
        var targets = candidates[cacheKey] ?? [:]
        var isComplete = true

        if targets.isEmpty {
            let externalIDs: ExternalIDs
            if media.externalIDs.isEmpty {
                do {
                    externalIDs = try await services.detail.mediaItem(id: media.id).externalIDs
                } catch {
                    if !error.isCancellation {
                        ErrorReporter.capture(error)
                    }
                    return []
                }
            } else {
                externalIDs = media.externalIDs
            }
            for source in sources {
                do {
                    if let target = try await source.watchlistTarget(
                        kind: kind,
                        externalIDs: externalIDs,
                        plexGuidID: media.plexGuidID,
                    ) {
                        targets[source.id] = target
                    }
                } catch {
                    isComplete = false
                    if !error.isCancellation, !error.isTrackerTransient {
                        ErrorReporter.capture(error)
                    }
                }
            }
            if isComplete {
                candidates[cacheKey] = targets
            }
        }

        var options: [ExploreWatchlistOption] = []
        for source in sources {
            guard let target = targets[source.id], let watchlist = source.watchlist else { continue }
            try? await watchlist.load()
            options.append(ExploreWatchlistOption(source: source.id, target: target, watchlist: watchlist))
        }
        return options
    }
}
