import Foundation
import Observation

/// What the settings show about one service for the active profile.
struct TrackerAccountState: Equatable {
    var isConnected = false
    var settings = TrackerAccountSettings()
    var issue: TrackerIssue?
}

/// A connected account, kept by the playbacks that began with it even after a profile switch.
@MainActor
final class TrackerBinding {
    let profileID: String
    let service: TrackerService
    let client: any TrackerClient
    var channel: TrackerPlaybackChannel!
    var isActive = true
    var holdUntil: Date?

    init(profileID: String, service: TrackerService, client: any TrackerClient) {
        self.profileID = profileID
        self.service = service
        self.client = client
    }
}

/// The single point through which every tracker write leaves the app. Trackers only ever receive: the media server
/// stays the source of the watch state, and nothing here reaches the playback or watched UI when it fails.
@MainActor
@Observable
final class TrackerCoordinator {
    typealias ClientFactory = @MainActor (
        TrackerService,
        TrackerSession,
        _ onUpdated: @escaping (TrackerSession) -> Void,
        _ onInvalidated: @escaping () -> Void,
    ) -> any TrackerClient

    static let shared = TrackerCoordinator(isDisabled: isDemoMode)

    private static var isDemoMode: Bool {
        #if DEBUG
            DemoMode.isEnabled
        #else
            false
        #endif
    }

    private static let batchSize = 50
    private static let throttledHold: TimeInterval = 5 * 60
    private static let rateLimitFallbackHold: TimeInterval = 60

    private(set) var states: [TrackerService: TrackerAccountState] = [:]
    private(set) var activeProfileID: String?

    @ObservationIgnored private let isDisabled: Bool
    @ObservationIgnored private let store: TrackerAccountStore
    @ObservationIgnored private let queue: TrackerWriteQueue
    @ObservationIgnored private let makeClient: ClientFactory
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let resolver = TrackerItemResolver()
    @ObservationIgnored private var bindings: [TrackerService: TrackerBinding] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherFlush = false

    init(
        isDisabled: Bool = false,
        store: TrackerAccountStore? = nil,
        queue: TrackerWriteQueue? = nil,
        now: @escaping () -> Date = Date.init,
        makeClient: @escaping ClientFactory = TrackerCoordinator.defaultClient,
    ) {
        self.isDisabled = isDisabled
        self.store = store ?? TrackerAccountStore()
        self.queue = queue ?? TrackerWriteQueue()
        self.now = now
        self.makeClient = makeClient
    }

    private static func defaultClient(
        service: TrackerService,
        session: TrackerSession,
        onUpdated: @escaping (TrackerSession) -> Void,
        onInvalidated: @escaping () -> Void,
    ) -> any TrackerClient {
        switch service {
        case .trakt: TraktClient(session: session, onUpdated: onUpdated, onInvalidated: onInvalidated)
        case .simkl: SimklClient(session: session, onUpdated: onUpdated, onInvalidated: onInvalidated)
        }
    }

    func state(for service: TrackerService) -> TrackerAccountState {
        states[service] ?? TrackerAccountState()
    }

    // MARK: - Profiles

    /// A playback in progress keeps writing through the account it began with.
    func activate(profileID: String?) {
        guard !isDisabled, profileID != activeProfileID else { return }
        activeProfileID = profileID
        bindings = [:]
        states = [:]
        guard let profileID else { return }
        for service in TrackerService.allCases {
            if let session = store.session(service, profileID: profileID) {
                bindings[service] = makeBinding(service: service, session: session, profileID: profileID)
            }
            refreshState(service)
        }
        flushQueue()
    }

    func removeProfile(_ profileID: String) {
        for service in TrackerService.allCases {
            store.removeAccount(service, profileID: profileID)
        }
        queue.removeAll(profileID: profileID)
        if activeProfileID == profileID {
            activate(profileID: nil)
        }
    }

    // MARK: - Accounts

    func connect(_ service: TrackerService, session: TrackerSession) async {
        guard let profileID = activeProfileID else { return }
        bindings[service]?.isActive = false
        store.saveSession(session, service: service, profileID: profileID)
        let binding = makeBinding(service: service, session: session, profileID: profileID)
        bindings[service] = binding

        var settings = store.settings(service, profileID: profileID)
        let previousUsername = settings.username
        settings.needsReconnect = false
        settings.isEnabled = true
        do {
            settings.username = try await binding.client.currentUser().username
        } catch {
            if !error.isCancellation, !error.isTrackerTransient {
                ErrorReporter.capture(error)
            }
        }
        // Writes queued under another account must not land on this one.
        if previousUsername != nil, previousUsername != settings.username {
            queue.removeAll(profileID: profileID, service: service)
        }
        store.saveSettings(settings, service: service, profileID: profileID)
        refreshState(service)
        flushQueue()
    }

    func disconnect(_ service: TrackerService) async {
        guard let profileID = activeProfileID else { return }
        let binding = bindings.removeValue(forKey: service)
        binding?.isActive = false
        store.removeAccount(service, profileID: profileID)
        queue.removeAll(profileID: profileID, service: service)
        refreshState(service)
        await binding?.client.revoke()
    }

    func setEnabled(_ isEnabled: Bool, for service: TrackerService) {
        updateSettings(service) { $0.isEnabled = isEnabled }
        if isEnabled {
            flushQueue()
        }
    }

    func setLibrary(_ libraryKey: String, isExcluded: Bool, for service: TrackerService) {
        updateSettings(service) { settings in
            if isExcluded {
                settings.excludedLibraries.insert(libraryKey)
            } else {
                settings.excludedLibraries.remove(libraryKey)
            }
        }
    }

    private func updateSettings(_ service: TrackerService, _ change: (inout TrackerAccountSettings) -> Void) {
        guard let profileID = activeProfileID else { return }
        var settings = store.settings(service, profileID: profileID)
        change(&settings)
        store.saveSettings(settings, service: service, profileID: profileID)
        refreshState(service)
    }

    private func refreshState(_ service: TrackerService) {
        guard let profileID = activeProfileID else { return }
        var state = states[service] ?? TrackerAccountState()
        state.isConnected = bindings[service] != nil
        state.settings = store.settings(service, profileID: profileID)
        states[service] = state
    }

    private func makeBinding(service: TrackerService, session: TrackerSession, profileID: String) -> TrackerBinding {
        // The binding is created after the client, whose callbacks need to tell it apart from a later reconnection.
        weak var bound: TrackerBinding?
        let client = makeClient(service, session, { [weak self] renewed in
            guard bound?.isActive == true else { return }
            self?.store.saveSession(renewed, service: service, profileID: profileID)
        }, { [weak self] in
            guard let self, let bound, bound.isActive else { return }
            handleExpiredSession(of: bound)
        })
        let binding = TrackerBinding(profileID: profileID, service: service, client: client)
        bound = binding
        binding.channel = TrackerPlaybackChannel(
            client: client,
            isAvailable: { [weak self, weak binding] in
                guard let self, let binding else { return false }
                return canSend(to: binding)
            },
            onFailure: { [weak self, weak binding] report, error in
                guard let self, let binding else { return }
                handlePlaybackFailure(report, error: error, binding: binding)
            },
            now: now,
        )
        return binding
    }

    private func handleExpiredSession(of binding: TrackerBinding) {
        binding.isActive = false
        store.deleteSession(binding.service, profileID: binding.profileID)
        var settings = store.settings(binding.service, profileID: binding.profileID)
        settings.needsReconnect = true
        store.saveSettings(settings, service: binding.service, profileID: binding.profileID)
        if bindings[binding.service] === binding {
            bindings[binding.service] = nil
            refreshState(binding.service)
        }
    }

    // MARK: - Playback

    /// Nil when nothing would be reported: Live TV and clips never call this, and other kinds are not tracked.
    func beginPlayback(
        of media: MediaItem,
        detail: any MediaDetailService,
        resumeOffset: TimeInterval?,
    ) -> TrackerPlaybackSession? {
        guard media.type == .movie || media.type == .episode else { return nil }
        let candidates = enabledBindings
        guard !candidates.isEmpty else { return nil }
        let session = TrackerPlaybackSession(resumeOffset: resumeOffset, now: now)
        Task {
            do {
                let item = try await resolver.resolve(media, detail: detail)
                let allowed = try await allowedBindings(candidates, media: media, detail: detail)
                session.resolve(item: item, bindings: allowed)
            } catch {
                session.resolve(item: nil, bindings: [])
                reportResolutionFailure(error)
            }
        }
        return session
    }

    private func handlePlaybackFailure(_ report: TrackerPlaybackReport, error: Error, binding: TrackerBinding) {
        guard binding.isActive, isEnabled(binding) else { return }
        let wasWatched = report.event == .stop && report.progress >= binding.client.policy.watchedProgress
        switch classify(error, binding: binding) {
        case .keep, .count:
            // Without this the watch would be lost: a failed `start` or `pause` loses nothing the next event won't fix.
            guard wasWatched else { return }
            queue.enqueue([TrackerQueuedWrite(
                profileID: binding.profileID,
                service: binding.service,
                action: .add,
                item: report.item,
                watchedAt: report.date,
            )])
        case .drop:
            break
        }
    }

    // MARK: - Watched marks

    /// Called once the server applied the change. A season or a series goes out as its episodes.
    func setPlayed(_ played: Bool, item: MediaItem, detail: any MediaDetailService) {
        let candidates = enabledBindings
        guard !candidates.isEmpty else { return }
        let date = now()
        Task {
            do {
                let episodes = try await resolver.expand(item, detail: detail)
                await enqueue(episodes, action: played ? .add : .remove, at: date, bindings: candidates, detail: detail)
            } catch {
                reportResolutionFailure(error)
            }
        }
    }

    /// A watch that did not go through the streaming player: a download or an external player. The date is when it
    /// actually happened, which can be days before the server was reachable again.
    func noteWatched(itemID: String, at date: Date, detail: any MediaDetailService) {
        let candidates = enabledBindings
        guard !candidates.isEmpty else { return }
        Task {
            do {
                let item = try await detail.mediaItem(id: itemID)
                await enqueue([item], action: .add, at: date, bindings: candidates, detail: detail)
            } catch {
                reportResolutionFailure(error)
            }
        }
    }

    private func enqueue(
        _ media: [MediaItem],
        action: TrackerQueuedWrite.Action,
        at date: Date,
        bindings: [TrackerBinding],
        detail: any MediaDetailService,
    ) async {
        guard let first = media.first else { return }
        do {
            let allowed = try await allowedBindings(bindings, media: first, detail: detail)
            var items: [TrackerItem] = []
            for element in media {
                if let item = try await resolver.resolve(element, detail: detail) {
                    items.append(item)
                }
            }
            queue.enqueue(allowed.flatMap { binding in
                items.map { item in
                    TrackerQueuedWrite(
                        profileID: binding.profileID,
                        service: binding.service,
                        action: action,
                        item: item,
                        watchedAt: action == .add ? date : nil,
                    )
                }
            })
            flushQueue()
        } catch {
            reportResolutionFailure(error)
        }
    }

    // MARK: - Queue

    func flushQueue() {
        guard !isDisabled else { return }
        guard flushTask == nil else {
            needsAnotherFlush = true
            return
        }
        flushTask = Task { [weak self] in
            await self?.runFlushes()
        }
    }

    /// Waits for the flush in progress, if any.
    func waitForFlush() async {
        while let flushTask {
            await flushTask.value
        }
    }

    private func runFlushes() async {
        repeat {
            needsAnotherFlush = false
            for binding in enabledBindings {
                await flush(binding)
            }
        } while needsAnotherFlush
        flushTask = nil
    }

    private func flush(_ binding: TrackerBinding) async {
        let pending = queue.pending(profileID: binding.profileID, service: binding.service)
        for action in [TrackerQueuedWrite.Action.remove, .add] {
            let writes = pending.filter { $0.action == action }
            for start in stride(from: 0, to: writes.count, by: Self.batchSize) {
                guard canSend(to: binding) else { return }
                let batch = Array(writes[start ..< min(start + Self.batchSize, writes.count)])
                let ids = Set(batch.map(\.id))
                do {
                    switch action {
                    case .add:
                        try await binding.client.addToHistory(batch.map {
                            TrackerHistoryEntry(item: $0.item, watchedAt: $0.watchedAt)
                        })
                    case .remove:
                        try await binding.client.removeFromHistory(batch.map(\.item))
                    }
                    queue.remove(ids: ids)
                } catch {
                    switch classify(error, binding: binding) {
                    case .drop:
                        queue.remove(ids: ids)
                    case .count:
                        queue.recordFailure(ids: ids)
                        return
                    case .keep:
                        return
                    }
                }
            }
        }
    }

    // MARK: - Failures

    private enum FailureDecision {
        /// Nothing can come of retrying this write.
        case drop
        /// Not the write's fault: retried without counting.
        case keep
        /// Retried, a limited number of times.
        case count
    }

    private func classify(_ error: Error, binding: TrackerBinding) -> FailureDecision {
        if error.isCancellation {
            return .keep
        }
        guard let apiError = error as? TrackerAPIError else {
            guard !error.isTrackerTransient else { return .keep }
            ErrorReporter.capture(error)
            return .count
        }
        switch apiError {
        case .notFound, .conflict:
            return .drop
        case .unauthorized, .sessionExpired, .writeLocked, .unavailable:
            return .keep
        case let .rateLimited(retryAfter):
            hold(binding, for: retryAfter ?? Self.rateLimitFallbackHold)
            return .keep
        case .throttled:
            hold(binding, for: Self.throttledHold)
            return .keep
        case .accountLimit:
            holdUntilNextLaunch(binding, issue: .accountLimit)
            return .keep
        case .accountLocked:
            holdUntilNextLaunch(binding, issue: .accountLocked)
            return .keep
        case .server:
            return .count
        case .unexpected, .invalidResponse:
            ErrorReporter.capture(error)
            return .count
        }
    }

    private func hold(_ binding: TrackerBinding, for duration: TimeInterval) {
        binding.holdUntil = now().addingTimeInterval(duration)
    }

    private func holdUntilNextLaunch(_ binding: TrackerBinding, issue: TrackerIssue) {
        binding.holdUntil = .distantFuture
        guard bindings[binding.service] === binding else { return }
        states[binding.service]?.issue = issue
    }

    private func isHeld(_ binding: TrackerBinding) -> Bool {
        guard let holdUntil = binding.holdUntil else { return false }
        return holdUntil > now()
    }

    private func isEnabled(_ binding: TrackerBinding) -> Bool {
        store.settings(binding.service, profileID: binding.profileID).isEnabled
    }

    private func canSend(to binding: TrackerBinding) -> Bool {
        binding.isActive && !isHeld(binding) && isEnabled(binding)
    }

    private func reportResolutionFailure(_ error: Error) {
        guard !error.isCancellation, !error.isTrackerTransient else { return }
        ErrorReporter.capture(error)
    }

    // MARK: - Filtering

    private var enabledBindings: [TrackerBinding] {
        guard !isDisabled, let activeProfileID else { return [] }
        return TrackerService.allCases.compactMap { service in
            guard let binding = bindings[service],
                  store.settings(service, profileID: activeProfileID).isEnabled
            else { return nil }
            return binding
        }
    }

    /// Only asks the server for the library when a filter makes the answer matter.
    private func allowedBindings(
        _ bindings: [TrackerBinding],
        media: MediaItem,
        detail: any MediaDetailService,
    ) async throws -> [TrackerBinding] {
        let filtered = bindings.map { binding in
            (binding, store.settings(binding.service, profileID: binding.profileID).excludedLibraries)
        }
        guard filtered.contains(where: { !$0.1.isEmpty }) else { return bindings }
        let library = try await detail.libraryID(for: media)
            .map { Self.libraryKey(server: media.identity.server, libraryID: $0) }
        return filtered.compactMap { binding, excluded in
            if excluded.isEmpty {
                return binding
            }
            guard let library, !excluded.contains(library) else { return nil }
            return binding
        }
    }

    static func libraryKey(server: ServerIdentity, libraryID: String) -> String {
        "\(server.stableKey)|\(libraryID)"
    }
}

extension Error {
    /// A network failure says nothing about the tracker, or about Strimr.
    var isTrackerTransient: Bool {
        self is URLError || isHostUnreachable
    }
}
