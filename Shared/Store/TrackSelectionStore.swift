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
            defaults.set(try JSONEncoder().encode(envelope), forKey: storageKey)
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
        let subtitleIsOff: Bool
        if case .off = preference.subtitle {
            subtitleIsOff = true
        } else {
            subtitleIsOff = false
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
        let audioTracks = tracks
        if let streamIndex = preference.audioStreamIndex,
           let exact = audioTracks.first(where: { $0.id == streamIndex || $0.sourceIndex == streamIndex })
        {
            return exact.id ?? exact.sourceIndex
        }
        guard preference.audioLanguage != nil
            || preference.audioTitle != nil
            || preference.audioCodec != nil
        else { return nil }
        let candidates = audioTracks.filter { track in
            guard let language = preference.audioLanguage else { return true }
            return normalized(track.language) == normalized(language)
        }
        return candidates
            .map { track in (track, audioMatchScore(track, preference: preference)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }
            .flatMap { $0.0.id ?? $0.0.sourceIndex }
    }

    private func resolveSubtitleTrack(
        preference: MediaTrackPreference,
        tracks: [MediaTrackMetadata],
    ) -> Int? {
        guard case let .track(streamIndex, language, title, codec, isForced, isHearingImpaired) = preference.subtitle else {
            return nil
        }
        if let streamIndex,
           let exact = tracks.first(where: { $0.id == streamIndex || $0.sourceIndex == streamIndex })
        {
            return exact.id ?? exact.sourceIndex
        }
        guard language != nil || title != nil || !codec.isEmpty else { return nil }
        let candidates = tracks.filter { track in
            guard let language else { return true }
            return normalized(track.language) == normalized(language)
        }
        return candidates
            .map { track in
                (track, subtitleMatchScore(
                    track,
                    language: language,
                    title: title,
                    codec: codec,
                    isForced: isForced,
                    isHearingImpaired: isHearingImpaired,
                ))
            }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }
            .flatMap { $0.0.id ?? $0.0.sourceIndex }
    }

    private func audioMatchScore(
        _ track: MediaTrackMetadata,
        preference: MediaTrackPreference,
    ) -> Int {
        var score = 0
        if let language = preference.audioLanguage, normalized(track.language) == normalized(language) { score += 4 }
        if let title = preference.audioTitle,
           normalized(track.displayTitle) == normalized(title) || normalized(track.title) == normalized(title)
        { score += 3 }
        if let codec = preference.audioCodec, normalized(track.codec) == normalized(codec) { score += 2 }
        if let hearingImpaired = preference.audioIsHearingImpaired,
           track.isHearingImpaired == hearingImpaired
        { score += 1 }
        return score
    }

    private func subtitleMatchScore(
        _ track: MediaTrackMetadata,
        language: String?,
        title: String?,
        codec: String,
        isForced: Bool,
        isHearingImpaired: Bool?,
    ) -> Int {
        var score = 0
        if let language, normalized(track.language) == normalized(language) { score += 4 }
        if let title,
           normalized(track.displayTitle) == normalized(title) || normalized(track.title) == normalized(title)
        { score += 3 }
        if !codec.isEmpty, normalized(track.codec) == normalized(codec) { score += 2 }
        if track.isForced == isForced { score += 1 }
        if let isHearingImpaired, track.isHearingImpaired == isHearingImpaired { score += 1 }
        return score
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
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
