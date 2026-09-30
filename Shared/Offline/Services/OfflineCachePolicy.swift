import Foundation

/// Read/write policy shared by the cache decorators of one server and owner.
/// Reachable: network first, then the response is written to the cache. Transport failure: the server is flagged
/// unreachable and the cache answers. Unreachable: cache only, `MediaUnavailableOffline` when nothing is cached.
@MainActor
final class OfflineCachePolicy {
    let owner: MediaOwner
    let store: OfflineStore
    let coordinator: OfflineCoordinator

    init(owner: MediaOwner, store: OfflineStore, coordinator: OfflineCoordinator) {
        self.owner = owner
        self.store = store
        self.coordinator = coordinator
    }

    var isUnreachable: Bool {
        coordinator.isUnreachable(owner.server)
    }

    func read<T>(
        network: () async throws -> T,
        write: (T) -> Void,
        fallback: () -> T?,
        onNotFound: (() -> Void)? = nil,
    ) async throws -> T {
        if isUnreachable {
            if let cached = fallback() {
                return cached
            }
            throw MediaUnavailableOffline()
        }
        do {
            let value = try await network()
            coordinator.reportSuccess(on: owner.server)
            write(value)
            return value
        } catch {
            if error.isTransportFailure {
                coordinator.reportTransportFailure(on: owner.server)
                if let cached = fallback() {
                    return cached
                }
                throw MediaUnavailableOffline()
            }
            if error.isNotFound {
                onNotFound?()
            }
            throw error
        }
    }

    /// Operations that only make sense online (favorites, watchlist, manual watched state, subtitles…).
    func online<T>(_ operation: () async throws -> T) async throws -> T {
        guard !isUnreachable else { throw MediaUnavailableOffline() }
        do {
            let value = try await operation()
            coordinator.reportSuccess(on: owner.server)
            return value
        } catch {
            if error.isTransportFailure {
                coordinator.reportTransportFailure(on: owner.server)
                throw MediaUnavailableOffline()
            }
            throw error
        }
    }

    /// Items not yet synchronized carry local progress that must win over server payloads.
    func overlayLocalProgress(_ items: [MediaItem]) -> [MediaItem] {
        let states = store.watchStates(itemIDs: items.map(\.id), owner: owner, localOnly: true)
        guard !states.isEmpty else { return items }
        return items.map { item in states[item.id].map { item.applying($0) } ?? item }
    }

    func overlayLocalProgress(_ items: [MediaDisplayItem]) -> [MediaDisplayItem] {
        let playable = items.compactMap(\.playableItem)
        let states = store.watchStates(itemIDs: playable.map(\.id), owner: owner, localOnly: true)
        guard !states.isEmpty else { return items }
        return items.map { item in
            guard case let .playable(media) = item, let state = states[media.id] else { return item }
            return .playable(media.applying(state))
        }
    }
}
