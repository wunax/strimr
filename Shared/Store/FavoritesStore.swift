import Foundation
import Observation

@MainActor
@Observable
final class FavoritesStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "strimr.favorites.v1"

    private var recordsByScope: [String: [PlexFavoriteSnapshot]]

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([String: [PlexFavoriteSnapshot]].self, from: data)
        {
            recordsByScope = stored
        } else {
            recordsByScope = [:]
        }
    }

    func favorites(for scope: FavoriteScope) -> [PlexFavoriteSnapshot] {
        recordsByScope[scope.storageKey, default: []]
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    func contains(mediaID: String, in scope: FavoriteScope) -> Bool {
        recordsByScope[scope.storageKey, default: []].contains { $0.id == mediaID }
    }

    func setFavorite(
        _ favorite: Bool,
        snapshot: PlexFavoriteSnapshot,
        in scope: FavoriteScope,
    ) {
        var records = recordsByScope[scope.storageKey, default: []]
        records.removeAll { $0.id == snapshot.id }
        if favorite {
            records.append(snapshot)
        }
        recordsByScope[scope.storageKey] = records
        persist()
    }

    /// Moves the local favorites of a profile to another profile id, on every server.
    func renameProfile(from oldProfileID: String, to newProfileID: String) {
        guard oldProfileID != newProfileID else { return }
        var changed = false
        for (key, records) in recordsByScope {
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[2] == oldProfileID else { continue }
            let newKey = [String(parts[0]), String(parts[1]), newProfileID].joined(separator: "|")
            recordsByScope[newKey, default: []].append(contentsOf: records)
            recordsByScope[key] = nil
            changed = true
        }
        if changed {
            persist()
        }
    }

    func removeProfile(_ profileID: String) {
        let keys = recordsByScope.keys
            .filter { $0.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init) == profileID }
        guard !keys.isEmpty else { return }
        for key in keys {
            recordsByScope[key] = nil
        }
        persist()
    }

    private func persist() {
        do {
            try defaults.set(JSONEncoder().encode(recordsByScope), forKey: storageKey)
        } catch {
            ErrorReporter.capture(error)
        }
    }
}
