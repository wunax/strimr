import Foundation

nonisolated struct TrackerQueuedWrite: Codable, Equatable, Identifiable, Sendable {
    enum Action: String, Codable, Sendable {
        case add
        case remove
    }

    var id = UUID()
    let profileID: String
    let service: TrackerService
    let action: Action
    let item: TrackerItem
    let watchedAt: Date?
    var attempts = 0

    var mergeKey: String {
        [profileID, service.rawValue, item.rowKey].joined(separator: "|")
    }
}

/// History writes waiting to reach a tracker, so a failure does not lose a watch. Stored in `UserDefaults` rather than
/// the offline database, which tvOS does not build.
@MainActor
final class TrackerWriteQueue {
    static let maxCount = 500
    static let maxAttempts = 5

    private static let storageKey = "strimr.trackers.queue"

    private let defaults: UserDefaults
    private(set) var writes: [TrackerQueuedWrite]

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        writes = userDefaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([TrackerQueuedWrite].self, from: $0) } ?? []
    }

    /// The latest intent about a remote row replaces the previous one: "watched" then "unwatched" leaves "unwatched".
    func enqueue(_ newWrites: [TrackerQueuedWrite]) {
        guard !newWrites.isEmpty else { return }
        let replaced = Set(newWrites.map(\.mergeKey))
        writes.removeAll { replaced.contains($0.mergeKey) }
        var seen = Set<String>()
        let latest = newWrites.reversed().filter { seen.insert($0.mergeKey).inserted }.reversed()
        writes.append(contentsOf: latest)
        if writes.count > Self.maxCount {
            writes.removeFirst(writes.count - Self.maxCount)
        }
        save()
    }

    func pending(profileID: String, service: TrackerService) -> [TrackerQueuedWrite] {
        writes.filter { $0.profileID == profileID && $0.service == service }
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        writes.removeAll { ids.contains($0.id) }
        save()
    }

    /// Counts a failed attempt, and gives up on a write once it has failed too many times.
    func recordFailure(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for index in writes.indices where ids.contains(writes[index].id) {
            writes[index].attempts += 1
        }
        writes.removeAll { $0.attempts >= Self.maxAttempts }
        save()
    }

    func removeAll(profileID: String, service: TrackerService? = nil) {
        writes.removeAll { $0.profileID == profileID && (service == nil || $0.service == service) }
        save()
    }

    private func save() {
        if writes.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(try? JSONEncoder().encode(writes), forKey: Self.storageKey)
        }
    }
}
