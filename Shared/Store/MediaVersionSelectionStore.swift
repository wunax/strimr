import Foundation
import Observation

struct MediaVersionSelectionRecord: Codable, Hashable, Sendable {
    let account: TrackSelectionAccount
    let scope: TrackSelectionScope
    let preference: MediaVersionPreference
}

/// Version choices per movie or series, independent of `rememberTrackSelections`: they are explicit picks.
@MainActor
@Observable
final class MediaVersionSelectionStore {
    private struct Envelope: Codable {
        let version: Int
        let records: [MediaVersionSelectionRecord]
    }

    static let maximumRecordCount = 500

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "strimr.versionSelections"
    @ObservationIgnored private let schemaVersion = 1

    private(set) var records: [MediaVersionSelectionRecord]

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        if let data = defaults.data(forKey: storageKey),
           let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           envelope.version == schemaVersion
        {
            records = envelope.records
        } else {
            records = []
        }
    }

    func preference(
        for scope: TrackSelectionScope,
        account: TrackSelectionAccount,
    ) -> MediaVersionPreference? {
        records.first { $0.account == account && $0.scope == scope }?.preference
    }

    func save(
        _ preference: MediaVersionPreference,
        for scope: TrackSelectionScope,
        account: TrackSelectionAccount,
    ) {
        records.removeAll { $0.account == account && $0.scope == scope }
        records.append(MediaVersionSelectionRecord(account: account, scope: scope, preference: preference))
        if records.count > Self.maximumRecordCount {
            records = Array(
                records
                    .sorted { $0.preference.updatedAt > $1.preference.updatedAt }
                    .prefix(Self.maximumRecordCount),
            )
        }
        persist()
    }

    func remove(
        for scope: TrackSelectionScope,
        account: TrackSelectionAccount,
    ) {
        records.removeAll { $0.account == account && $0.scope == scope }
        persist()
    }

    func removeAll() {
        records = []
        persist()
    }

    private func persist() {
        do {
            let envelope = Envelope(version: schemaVersion, records: records)
            try defaults.set(JSONEncoder().encode(envelope), forKey: storageKey)
        } catch {
            ErrorReporter.capture(error)
        }
    }
}

extension MediaServices {
    private var versionSelectionAccount: TrackSelectionAccount {
        TrackSelectionAccount(server: identity, accountID: trackSelectionAccountIdentifier ?? "default")
    }

    func versionPreference(for scope: TrackSelectionScope) -> MediaVersionPreference? {
        versionSelectionStore?.preference(for: scope, account: versionSelectionAccount)
    }

    func versionRequest(for media: MediaItem) -> MediaVersionRequest {
        guard let scope = media.trackSelectionScope,
              let preference = versionPreference(for: scope)
        else { return .automatic }
        return .preferred(preference)
    }

    func rememberVersion(_ version: MediaFileVersion, for scope: TrackSelectionScope) {
        let preference = MediaVersionPreference(
            versionID: version.id,
            signature: version.signature,
            updatedAt: Date(),
        )
        versionSelectionStore?.save(preference, for: scope, account: versionSelectionAccount)
    }

    func forgetVersion(for scope: TrackSelectionScope) {
        versionSelectionStore?.remove(for: scope, account: versionSelectionAccount)
    }
}
