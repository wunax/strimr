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

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(recordsByScope), forKey: storageKey)
        } catch {
            ErrorReporter.capture(error)
        }
    }
}
