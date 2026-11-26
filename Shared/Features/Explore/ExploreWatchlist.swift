import Foundation
import Observation

/// A source's watchlist, loaded once per session. Changes show at once and are read back from the source a second
/// later, once it has settled.
@MainActor
@Observable
final class ExploreWatchlist {
    typealias Fetch = @MainActor () async throws -> [ExploreItem]
    typealias Mutate = @MainActor (_ add: Bool, _ target: ExploreWatchlistTarget) async throws -> Void

    nonisolated static let reloadDelay: Duration = .seconds(1)

    private(set) var items: [ExploreItem] = []
    private(set) var isLoaded = false
    private var overrides: [String: Bool] = [:]
    private var inFlight: Set<String> = []

    @ObservationIgnored private var keys: Set<String> = []
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let mutate: Mutate
    @ObservationIgnored private let reloadDelay: Duration
    @ObservationIgnored private var loadTask: Task<[ExploreItem], Error>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(reloadDelay: Duration = ExploreWatchlist.reloadDelay, fetch: @escaping Fetch, mutate: @escaping Mutate) {
        self.reloadDelay = reloadDelay
        self.fetch = fetch
        self.mutate = mutate
    }

    func load(force: Bool = false) async throws {
        if isLoaded, !force {
            return
        }
        if let loadTask {
            _ = try await loadTask.value
            return
        }
        let task = Task { try await fetch() }
        loadTask = task
        defer { loadTask = nil }
        let fetched = try await task.value
        items = fetched
        keys = fetched.reduce(into: Set<String>()) { $0.formUnion($1.watchlistTarget.keys) }
        overrides = [:]
        isLoaded = true
    }

    /// Nil until the watchlist has loaded once.
    func contains(_ target: ExploreWatchlistTarget) -> Bool? {
        let targetKeys = target.keys
        if let override = targetKeys.lazy.compactMap({ self.overrides[$0] }).first {
            return override
        }
        guard isLoaded else { return nil }
        return !keys.isDisjoint(with: targetKeys)
    }

    func isUpdating(_ target: ExploreWatchlistTarget) -> Bool {
        !inFlight.isDisjoint(with: target.keys)
    }

    /// Returns false when the same change is still being sent, which keeps a double tap from sending it twice.
    @discardableResult
    func set(_ onWatchlist: Bool, target: ExploreWatchlistTarget) async throws -> Bool {
        let targetKeys = target.keys
        guard !targetKeys.isEmpty, inFlight.isDisjoint(with: targetKeys) else { return false }
        inFlight.formUnion(targetKeys)
        defer { inFlight.subtract(targetKeys) }

        let previous = overrides
        for key in targetKeys {
            overrides[key] = onWatchlist
        }
        do {
            try await mutate(onWatchlist, target)
        } catch {
            overrides = previous
            throw error
        }
        scheduleReload()
        return true
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        let delay = reloadDelay
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            do {
                try await load(force: true)
            } catch {
                guard !error.isCancellation else { return }
                ErrorReporter.capture(error)
            }
        }
    }
}
