import Foundation

/// Replays the offline progress journal of the active owner once their server is reachable again.
/// Conflicts are resolved with "most recent wins": local state is pushed only when its event is more recent than
/// the server's last viewed date (or the server never saw the item); otherwise the server state replaces it.
@MainActor
final class ProgressSynchronizer {
    private let store: OfflineStore
    private var runningOwners: Set<MediaOwner> = []

    init(store: OfflineStore) {
        self.store = store
    }

    /// Returns `true` when every pending entry was synchronized.
    @discardableResult
    func synchronize(owner: MediaOwner, services: MediaServices) async -> Bool {
        guard runningOwners.insert(owner).inserted else { return false }
        defer { runningOwners.remove(owner) }

        let pending = store.pendingJournal(owner: owner)
        guard !pending.isEmpty else { return true }
        var allSynced = true
        for (itemID, entries) in Dictionary(grouping: pending, by: \.itemID) {
            guard !Task.isCancelled else { return false }
            let synced = await synchronize(itemID: itemID, entries: entries, owner: owner, services: services)
            allSynced = allSynced && synced
        }
        return allSynced
    }

    private func synchronize(
        itemID: String,
        entries: [ProgressJournalRecord],
        owner: MediaOwner,
        services: MediaServices,
    ) async -> Bool {
        let ids = entries.compactMap(\.id)
        let ordered = entries.sorted { $0.occurredAt < $1.occurredAt }
        guard let latest = ordered.last else { return true }
        let lastWatched = ordered.last { $0.event == ProgressJournalEvent.watched.rawValue }
        let lastPosition = ordered.last {
            $0.event != ProgressJournalEvent.watched.rawValue && $0.position > 0
        }

        do {
            let server = try await services.playback.serverWatchState(itemID: itemID)
            let serverDate = server.lastViewedAt

            if let serverDate, latest.occurredAt <= serverDate {
                // The server saw more recent activity: it wins, unless a local "watched" is newer than it.
                if let lastWatched, lastWatched.occurredAt > serverDate, !server.isPlayed {
                    try await services.playback.markItemWatched(itemID: itemID, at: lastWatched.occurredAt)
                }
            } else {
                if let lastWatched {
                    try await services.playback.markItemWatched(itemID: itemID, at: lastWatched.occurredAt)
                }
                // A rewatch started after the local "watched" still needs its position.
                if let lastPosition, lastWatched.map({ lastPosition.occurredAt > $0.occurredAt }) ?? true {
                    try await services.playback.pushItemPosition(
                        itemID: itemID,
                        position: lastPosition.position,
                        duration: lastPosition.duration,
                        at: lastPosition.occurredAt,
                    )
                }
            }

            store.markJournalSynced(ids: ids)
        } catch {
            return handle(error, ids: ids)
        }

        do {
            let refreshed = try await services.playback.serverWatchState(itemID: itemID)
            store.setWatchState(
                OfflineWatchState(
                    viewOffset: refreshed.viewOffset,
                    viewCount: refreshed.viewCount,
                    played: refreshed.isPlayed,
                    lastViewedAt: refreshed.lastViewedAt,
                    source: .server,
                ),
                itemID: itemID,
                owner: owner,
            )
        } catch {
            // The push succeeded; the local state is simply refreshed on the next online read.
            if !error.isCancellation, !error.isTransportFailure {
                ErrorReporter.capture(error)
            }
        }
        return true
    }

    private func handle(_ error: Error, ids: [Int64]) -> Bool {
        guard !Task.isCancelled, !error.isCancellation else { return false }
        if error.isNotFound {
            // The item was deleted on the server: nothing left to synchronize it with.
            store.markJournalSynced(ids: ids)
            return true
        }
        store.markJournalFailed(ids: ids, error: String(describing: type(of: error)))
        if !error.isTransportFailure {
            ErrorReporter.capture(error)
        }
        return false
    }
}
