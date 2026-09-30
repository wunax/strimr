import Foundation
import Observation

/// Owns the offline stack (store, availability, progress, synchronization, pinning). One instance per app process;
/// everything it manages is keyed by server and user so several servers can be active at once.
@MainActor
@Observable
final class OfflineCoordinator {
    enum ConnectivityBanner: Equatable {
        case offline
        case serverUnreachable
    }

    static let shared = OfflineCoordinator()

    @ObservationIgnored let store: OfflineStore?
    let availability = ServerAvailabilityMonitor()
    private(set) var activeOwners: Set<MediaOwner> = []
    private(set) var activeServers: [ServerIdentity] = []
    @ObservationIgnored private var sessionServices: [ServerIdentity: MediaServices] = [:]
    @ObservationIgnored private let synchronizer: ProgressSynchronizer?
    @ObservationIgnored let enrichment: OfflineEnrichmentService?
    @ObservationIgnored private var synchronizationTasks: [ServerIdentity: Task<Void, Never>] = [:]
    @ObservationIgnored private var reachabilityObservers: [(ServerIdentity) -> Void] = []
    @ObservationIgnored private var networkRestoredObservers: [() -> Void] = []

    private init() {
        do {
            let store = try OfflineStore(database: OfflineDatabase())
            self.store = store
            synchronizer = ProgressSynchronizer(store: store)
            enrichment = OfflineEnrichmentService(store: store)
        } catch {
            ErrorReporter.capture(error)
            store = nil
            synchronizer = nil
            enrichment = nil
        }
        availability.onServerBecameReachable = { [weak self] server in
            self?.serverBecameReachable(server)
        }
        availability.onNetworkPathRestored = { [weak self] in
            guard let self else { return }
            for observer in networkRestoredObservers {
                observer()
            }
        }
    }

    // MARK: - Session

    /// Registers the services of the current session. Passing `nil` clears every active owner (signed out).
    func activate(services: MediaServices?) {
        guard let services else {
            sessionServices = [:]
            activeOwners = []
            activeServers = []
            availability.untrackAll()
            return
        }
        for server in sessionServices.keys where server != services.identity {
            availability.untrack(server)
        }
        sessionServices = [services.identity: services]
        activeOwners = [services.owner]
        activeServers = [services.identity]
        store?.register(owner: services.owner)
        let probeURL = services.availabilityProbeURL
        availability.track(services.identity, probe: ServerAvailabilityMonitor.probe { probeURL?() })
        if availability.availability(for: services.identity) == .reachable {
            serverBecameReachable(services.identity)
        }
    }

    // MARK: - Availability

    func isUnreachable(_ server: ServerIdentity) -> Bool {
        availability.isUnreachable(server)
    }

    /// Every server of the session is unreachable.
    var isFullyOffline: Bool {
        !activeServers.isEmpty && activeServers.allSatisfy(availability.isUnreachable)
    }

    var banner: ConnectivityBanner? {
        guard !activeServers.isEmpty, activeServers.contains(where: availability.isUnreachable) else { return nil }
        return availability.hasNetworkPath ? .serverUnreachable : .offline
    }

    func reportTransportFailure(on server: ServerIdentity) {
        availability.reportTransportFailure(on: server)
    }

    func reportSuccess(on server: ServerIdentity) {
        availability.reportSuccess(on: server)
    }

    /// Services able to push progress for `owner` right now: the owner must be the signed-in user, since the
    /// server token belongs to them, and the server must not be known to be unreachable.
    func reachableServices(for owner: MediaOwner) -> MediaServices? {
        guard activeOwners.contains(owner),
              let services = sessionServices[owner.server],
              !availability.isUnreachable(owner.server)
        else { return nil }
        return services
    }

    /// Observers live as long as the app: they are registered by long-lived managers.
    func observeReachability(_ observer: @escaping (ServerIdentity) -> Void) {
        reachabilityObservers.append(observer)
    }

    func observeNetworkRestored(_ observer: @escaping () -> Void) {
        networkRestoredObservers.append(observer)
    }

    private func serverBecameReachable(_ server: ServerIdentity) {
        synchronizeProgress(on: server)
        for observer in reachabilityObservers {
            observer(server)
        }
    }

    // MARK: - Progress

    /// Pushes the pending progress journal of the active owner of `server`.
    func synchronizeProgress(on server: ServerIdentity) {
        guard let synchronizer,
              let services = sessionServices[server],
              !availability.isUnreachable(server),
              synchronizationTasks[server] == nil
        else { return }
        let owner = services.owner
        synchronizationTasks[server] = Task { [weak self] in
            await synchronizer.synchronize(owner: owner, services: services)
            self?.synchronizationTasks[server] = nil
        }
    }

    /// Synchronizes the journal and waits for the result; used before signing out.
    func synchronizeProgressNow(owner: MediaOwner) async -> Bool {
        guard let synchronizer, let services = reachableServices(for: owner) else {
            return pendingProgressCount(for: owner) == 0
        }
        await synchronizationTasks[owner.server]?.value
        return await synchronizer.synchronize(owner: owner, services: services)
            && pendingProgressCount(for: owner) == 0
    }

    func pendingProgressCount(for owner: MediaOwner) -> Int {
        store?.pendingJournalCount(owner: owner) ?? 0
    }

    // MARK: - Storage

    func setCacheLimit(megabytes: Int) {
        store?.cacheLimit = Int64(megabytes) * 1_000_000
        evictCacheIfNeeded()
    }

    func evictCacheIfNeeded() {
        guard let store else { return }
        store.evictCache(toFit: store.cacheLimit)
    }

    func storageSizes() -> OfflineStorageSizes {
        store?.storageSizes() ?? OfflineStorageSizes()
    }

    /// Empties the browsing cache only; downloads, pinned data and the progress journal are untouched.
    func clearCache() {
        store?.clearCache()
    }

    func makeRecorder(owner: MediaOwner, itemID: String, duration: TimeInterval?) -> PlaybackProgressRecorder? {
        guard let store else { return nil }
        return PlaybackProgressRecorder(
            owner: owner,
            itemID: itemID,
            duration: duration,
            store: store,
            coordinator: self,
        )
    }
}
