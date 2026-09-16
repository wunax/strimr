import Foundation
import Observation

struct TrackSelectionAccount: Codable, Hashable, Sendable {
    let server: ServerIdentity
    let accountID: String
}

enum TrackSelectionScope: Codable, Hashable, Sendable {
    case media(MediaIdentity)
    case series(MediaIdentity)
}

struct TrackSelectionRecord: Codable, Hashable, Sendable {
    let account: TrackSelectionAccount
    let scope: TrackSelectionScope
    let preference: MediaTrackPreference
    let updatedAt: Date
}

struct TrackSelectionResolution: Hashable, Sendable {
    let audioTrackID: Int?
    let subtitleTrackID: Int?
    let subtitleIsOff: Bool
}

@MainActor
@Observable
final class TrackSelectionStore {
    private struct Envelope: Codable {
        let version: Int
        let records: [TrackSelectionRecord]
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "strimr.trackSelections"
    @ObservationIgnored private let schemaVersion = 1

    private(set) var records: [TrackSelectionRecord]

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
    ) -> MediaTrackPreference? {
        records.first {
            $0.account == account && $0.scope == scope
        }?.preference
    }

    func save(
        _ preference: MediaTrackPreference,
        for scope: TrackSelectionScope,
        account: TrackSelectionAccount,
    ) {
        let record = TrackSelectionRecord(
            account: account,
            scope: scope,
            preference: preference,
            updatedAt: Date(),
        )
        records.removeAll { $0.account == account && $0.scope == scope }
        records.insert(record, at: 0)
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

extension MediaItem {
    var trackSelectionScope: TrackSelectionScope? {
        switch type {
        case .movie:
            .media(identity)
        case .episode:
            hierarchy.seriesID.map(TrackSelectionScope.series)
        case .series, .season, .clip, .collection, .playlist, .folder, .unknown:
            nil
        }
    }
}

@MainActor
final class TrackSelectionCoordinator {
    private let store: TrackSelectionStore
    private let settingsManager: SettingsManager

    init(store: TrackSelectionStore, settingsManager: SettingsManager) {
        self.store = store
        self.settingsManager = settingsManager
    }

    var isEnabled: Bool {
        settingsManager.playback.rememberTrackSelections
    }

    func preference(
        for media: MediaItem,
        server: ServerIdentity,
        accountIdentifier: String,
    ) -> MediaTrackPreference? {
        guard let scope = media.trackSelectionScope else { return nil }
        guard let preference = preference(
            for: scope,
            server: server,
            accountIdentifier: accountIdentifier,
        ) else { return nil }
        return media.type == .episode ? preference.matchingAcrossItems : preference
    }

    func preference(
        for scope: TrackSelectionScope,
        server: ServerIdentity,
        accountIdentifier: String,
    ) -> MediaTrackPreference? {
        guard settingsManager.playback.rememberTrackSelections else { return nil }
        let account = TrackSelectionAccount(server: server, accountID: accountIdentifier)
        return store.preference(for: scope, account: account)
    }

    func resolvedSelection(
        for media: MediaItem,
        audioTracks: [MediaTrackMetadata],
        subtitleTracks: [MediaTrackMetadata],
        server: ServerIdentity,
        accountIdentifier: String,
    ) -> TrackSelectionResolution? {
        guard let scope = media.trackSelectionScope,
              let preference = preference(
                  for: scope,
                  server: server,
                  accountIdentifier: accountIdentifier,
              )
        else { return nil }
        return resolvedSelection(
            for: media.type == .episode ? preference.matchingAcrossItems : preference,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
        )
    }

    func resolvedSelection(
        for scope: TrackSelectionScope,
        audioTracks: [MediaTrackMetadata],
        subtitleTracks: [MediaTrackMetadata],
        server: ServerIdentity,
        accountIdentifier: String,
        matchingAcrossItems: Bool = false,
    ) -> TrackSelectionResolution? {
        guard let preference = preference(
            for: scope,
            server: server,
            accountIdentifier: accountIdentifier,
        ) else { return nil }
        return resolvedSelection(
            for: matchingAcrossItems ? preference.matchingAcrossItems : preference,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
        )
    }

    private func resolvedSelection(
        for preference: MediaTrackPreference,
        audioTracks: [MediaTrackMetadata],
        subtitleTracks: [MediaTrackMetadata],
    ) -> TrackSelectionResolution {
        let subtitleIsOff = if case .off = preference.subtitle {
            true
        } else {
            false
        }
        return TrackSelectionResolution(
            audioTrackID: resolveAudioTrack(preference: preference, tracks: audioTracks),
            subtitleTrackID: resolveSubtitleTrack(preference: preference, tracks: subtitleTracks),
            subtitleIsOff: subtitleIsOff,
        )
    }

    private func resolveAudioTrack(
        preference: MediaTrackPreference,
        tracks: [MediaTrackMetadata],
    ) -> Int? {
        guard let match = TrackSelectionMatcher.bestAudioMatch(
            preference: preference,
            candidates: tracks,
            descriptor: \.trackSelectionMatchDescriptor,
        ) else {
            return nil
        }
        return match.id ?? match.sourceIndex
    }

    private func resolveSubtitleTrack(
        preference: MediaTrackPreference,
        tracks: [MediaTrackMetadata],
    ) -> Int? {
        TrackSelectionMatcher.bestSubtitleMatch(
            preference: preference.subtitle,
            candidates: tracks,
            descriptor: \.trackSelectionMatchDescriptor,
        ).flatMap { $0.id ?? $0.sourceIndex }
    }

    func rememberAudio(
        _ track: PlayerTrack,
        for media: MediaItem,
        server: ServerIdentity,
        accountIdentifier: String,
    ) {
        guard settingsManager.playback.rememberTrackSelections else { return }
        guard track.type == .audio,
              let scope = media.trackSelectionScope
        else { return }

        let account = TrackSelectionAccount(server: server, accountID: accountIdentifier)
        var preference = store.preference(for: scope, account: account) ?? .serverDefault
        preference.audioStreamIndex = track.providerStreamID ?? track.ffIndex
        preference.audioLanguage = track.language
        preference.audioTitle = track.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? track.title
            : nil
        preference.audioCodec = track.codec
        preference.audioIsHearingImpaired = track.isHearingImpaired
        preference.audioIsCommentary = track.isCommentary
        store.save(preference, for: scope, account: account)
    }

    func rememberAudio(
        _ track: MediaTrackMetadata,
        for media: MediaItem,
        server: ServerIdentity,
        accountIdentifier: String,
    ) {
        guard let scope = media.trackSelectionScope else { return }
        rememberAudio(
            track,
            forScope: scope,
            server: server,
            accountIdentifier: accountIdentifier,
        )
    }

    func rememberAudio(
        _ track: MediaTrackMetadata,
        forScope scope: TrackSelectionScope,
        server: ServerIdentity,
        accountIdentifier: String,
    ) {
        guard settingsManager.playback.rememberTrackSelections else { return }

        let account = TrackSelectionAccount(server: server, accountID: accountIdentifier)
        var preference = store.preference(for: scope, account: account) ?? .serverDefault
        preference.audioStreamIndex = track.id ?? track.sourceIndex
        preference.audioLanguage = track.language
        preference.audioTitle = track.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? track.title
            : nil
        preference.audioCodec = track.codec
        preference.audioIsHearingImpaired = track.isHearingImpaired
        preference.audioIsCommentary = nil
        store.save(preference, for: scope, account: account)
    }

    func rememberSubtitle(
        _ track: PlayerTrack?,
        for media: MediaItem,
        server: ServerIdentity,
        accountIdentifier: String,
    ) {
        guard settingsManager.playback.rememberTrackSelections else { return }
        guard let scope = media.trackSelectionScope else { return }

        let account = TrackSelectionAccount(server: server, accountID: accountIdentifier)
        var preference = store.preference(for: scope, account: account) ?? .serverDefault
        if let track, track.type == .subtitle {
            preference.subtitle = .track(
                streamIndex: track.providerStreamID ?? track.ffIndex,
                language: track.language,
                title: track.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? track.title
                    : nil,
                codec: track.codec ?? "",
                isForced: track.isForced,
                isHearingImpaired: track.isHearingImpaired,
            )
        } else {
            preference.subtitle = .off
        }
        store.save(preference, for: scope, account: account)
    }

    func rememberSubtitle(
        _ track: MediaTrackMetadata?,
        for media: MediaItem,
        server: ServerIdentity,
        accountIdentifier: String,
    ) {
        guard let scope = media.trackSelectionScope else { return }
        rememberSubtitle(
            track,
            forScope: scope,
            server: server,
            accountIdentifier: accountIdentifier,
        )
    }

    func rememberSubtitle(
        _ track: MediaTrackMetadata?,
        forScope scope: TrackSelectionScope,
        server: ServerIdentity,
        accountIdentifier: String,
    ) {
        guard settingsManager.playback.rememberTrackSelections else { return }

        let account = TrackSelectionAccount(server: server, accountID: accountIdentifier)
        var preference = store.preference(for: scope, account: account) ?? .serverDefault
        if let track {
            preference.subtitle = .track(
                streamIndex: track.id ?? track.sourceIndex,
                language: track.language,
                title: track.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? track.title
                    : nil,
                codec: track.codec,
                isForced: track.isForced,
                isHearingImpaired: track.isHearingImpaired,
            )
        } else {
            preference.subtitle = .off
        }
        store.save(preference, for: scope, account: account)
    }

    func reset(
        for media: MediaItem,
        server: ServerIdentity,
        accountIdentifier: String,
    ) {
        guard let scope = media.trackSelectionScope else { return }
        store.remove(
            for: scope,
            account: TrackSelectionAccount(server: server, accountID: accountIdentifier),
        )
    }
}
