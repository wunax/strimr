import Foundation

/// Records progress of a downloaded file: every event goes to the local journal and watch state first (so
/// "Continue watching" and progress bars are immediately right), then is pushed live when the owner's server is
/// reachable. Unsynced entries are replayed by `ProgressSynchronizer`.
@MainActor
final class PlaybackProgressRecorder {
    static let watchedThreshold = 0.9

    private let owner: MediaOwner
    private let itemID: String
    private let store: OfflineStore
    private let coordinator: OfflineCoordinator
    private var duration: TimeInterval?
    private var hasStarted = false
    private var hasReportedWatched = false
    private var pushTask: Task<Void, Never>?

    init(
        owner: MediaOwner,
        itemID: String,
        duration: TimeInterval?,
        store: OfflineStore,
        coordinator: OfflineCoordinator,
    ) {
        self.owner = owner
        self.itemID = itemID
        self.duration = duration
        self.store = store
        self.coordinator = coordinator
    }

    /// Keeps the position of a stream interrupted by a lost server, so the download resumes there and the server is
    /// caught up by the synchronization.
    static func recordInterruptedStream(
        owner: MediaOwner,
        itemID: String,
        position: TimeInterval,
        duration: TimeInterval?,
        store: OfflineStore,
    ) {
        guard position > 0 else { return }
        let now = Date()
        let previous = store.watchState(itemID: itemID, owner: owner)
        store.setWatchState(
            OfflineWatchState(
                viewOffset: position,
                viewCount: previous?.viewCount ?? 0,
                played: previous?.played ?? false,
                lastViewedAt: now,
                source: .local,
            ),
            itemID: itemID,
            owner: owner,
        )
        _ = store.appendJournal(
            itemID: itemID,
            owner: owner,
            position: position,
            duration: duration,
            event: .stop,
            occurredAt: now,
            syncedAt: nil,
        )
    }

    /// Resume position using the same rules as streaming: finished items restart from the beginning.
    var resumePosition: TimeInterval? {
        guard let state = store.watchState(itemID: itemID, owner: owner),
              let offset = state.viewOffset, offset > 0
        else { return nil }
        if let duration, duration > 0, offset / duration >= Self.watchedThreshold {
            return nil
        }
        return offset
    }

    func record(position: TimeInterval, duration: TimeInterval?, isPaused: Bool) {
        if let duration, duration > 0 {
            self.duration = duration
        }
        // The player reports position 0 before seeking to the resume point; do not let it erase local progress.
        guard hasStarted || position >= 1 else { return }
        let event: ProgressJournalEvent
        let reportState: ItemPlaybackReportState
        if !hasStarted {
            hasStarted = true
            event = .start
            reportState = .started
        } else {
            event = isPaused ? .pause : .progress
            reportState = .progress
        }
        write(event: event, position: position, reportState: reportState, isPaused: isPaused)
        checkWatchedThreshold(position: position)
    }

    func stop(position: TimeInterval) {
        guard hasStarted else { return }
        write(event: .stop, position: position, reportState: .stopped, isPaused: true)
        checkWatchedThreshold(position: position)
    }

    func finish() {
        let position = duration ?? 0
        if hasStarted {
            write(event: .stop, position: position, reportState: .stopped, isPaused: true)
        }
        markWatched()
    }

    private func checkWatchedThreshold(position: TimeInterval) {
        guard let duration, duration > 0, position / duration >= Self.watchedThreshold else { return }
        markWatched()
    }

    private func markWatched() {
        guard !hasReportedWatched else { return }
        hasReportedWatched = true
        let now = Date()
        let previous = store.watchState(itemID: itemID, owner: owner)
        store.setWatchState(
            OfflineWatchState(
                viewOffset: nil,
                viewCount: (previous?.viewCount ?? 0) + 1,
                played: true,
                lastViewedAt: now,
                source: .local,
            ),
            itemID: itemID,
            owner: owner,
        )
        let journalID = store.appendJournal(
            itemID: itemID,
            owner: owner,
            position: duration ?? 0,
            duration: duration,
            event: .watched,
            occurredAt: now,
            syncedAt: nil,
        )
        push(journalID: journalID) { services, itemID in
            try await services.playback.markItemWatched(itemID: itemID, at: now)
        }
    }

    private func write(
        event: ProgressJournalEvent,
        position: TimeInterval,
        reportState: ItemPlaybackReportState,
        isPaused: Bool,
    ) {
        let now = Date()
        let previous = store.watchState(itemID: itemID, owner: owner)
        store.setWatchState(
            OfflineWatchState(
                viewOffset: position,
                viewCount: previous?.viewCount ?? 0,
                played: previous?.played ?? false,
                lastViewedAt: now,
                source: .local,
            ),
            itemID: itemID,
            owner: owner,
        )
        let journalID = store.appendJournal(
            itemID: itemID,
            owner: owner,
            position: position,
            duration: duration,
            event: event,
            occurredAt: now,
            syncedAt: nil,
        )
        let duration = duration
        push(journalID: journalID) { services, itemID in
            try await services.playback.reportItemPlayback(
                itemID: itemID,
                state: reportState,
                position: position,
                duration: duration,
                isPaused: isPaused,
            )
        }
    }

    private func push(
        journalID: Int64?,
        _ operation: @escaping @MainActor (MediaServices, String) async throws -> Void,
    ) {
        guard let journalID, let services = coordinator.reachableServices(for: owner) else { return }
        let previousTask = pushTask
        let itemID = itemID
        let store = store
        let owner = owner
        pushTask = Task { @MainActor in
            await previousTask?.value
            do {
                try await operation(services, itemID)
                store.markJournalSynced(ids: [journalID])
                if store.pendingJournal(owner: owner).allSatisfy({ $0.itemID != itemID }),
                   var state = store.watchState(itemID: itemID, owner: owner)
                {
                    state.source = .server
                    store.setWatchState(state, itemID: itemID, owner: owner)
                }
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                if error.isTransportFailure {
                    coordinator.reportTransportFailure(on: owner.server)
                } else {
                    store.markJournalFailed(ids: [journalID], error: String(describing: type(of: error)))
                    ErrorReporter.capture(error)
                }
            }
        }
    }
}
