import Foundation
import SwiftUI

/// Another copy of a title: on another server, or in another library of the same server.
struct MediaCopy: Identifiable, Hashable {
    let media: MediaItem
    let serverName: String
    /// Copies whose server is offline are listed greyed out.
    let isReachable: Bool
    var details = MediaCopyDetails()

    var id: MediaIdentity {
        media.identity
    }

    var server: ServerIdentity {
        media.identity.server
    }

    var resolutionRank: Int {
        media.resolutionRank
    }

    var libraryID: String? {
        media.librarySectionID ?? details.libraryID
    }

    /// Resolution first, then library, then server.
    static func sorted(_ copies: [MediaCopy]) -> [MediaCopy] {
        copies.sorted { lhs, rhs in
            if lhs.resolutionRank != rhs.resolutionRank {
                return lhs.resolutionRank > rhs.resolutionRank
            }
            let lhsLibrary = lhs.libraryID ?? ""
            let rhsLibrary = rhs.libraryID ?? ""
            if lhsLibrary != rhsLibrary {
                return lhsLibrary.localizedStandardCompare(rhsLibrary) == .orderedAscending
            }
            return lhs.serverName.localizedStandardCompare(rhs.serverName) == .orderedAscending
        }
    }
}

/// Finds the copies of a title on the profile's servers. Each server is searched by title and its results are kept
/// only when their ids match (§5.6): the title alone never makes a copy.
@MainActor
struct MediaCopyFinder {
    let sessionManager: SessionManager

    func copies(of media: MediaItem) async -> [MediaCopy] {
        let descriptor = media.matchDescriptor
        guard !descriptor.matchKeys.isEmpty else { return [] }
        let registry = sessionManager.registry
        let ready = registry.readyServers
        let sessions = registry.sessions.map { session in
            var session = session
            // Unreachable servers still answer from their cache; their copies are shown greyed out.
            if session.isEnabled, session.services != nil, session.status == .unreachable {
                session.status = .ready
            }
            return session
        }
        let title = media.type == .episode ? media.title : media.primaryLabel
        let result = await sessionManager.aggregation.fanOut(servers: sessions) { services in
            try await services.search.search(query: title, kinds: [media.type])
        }
        var seen: Set<MediaIdentity> = [media.identity]
        var copies: [MediaCopy] = []
        for session in sessions {
            for item in (result.value[session.identity] ?? []).compactMap(\.playableItem) {
                guard MediaMatching.matches(item.matchDescriptor, descriptor),
                      seen.insert(item.identity).inserted
                else { continue }
                copies.append(MediaCopy(
                    media: item,
                    serverName: session.name,
                    isReachable: ready.contains(session.identity),
                ))
            }
        }
        return MediaCopy.sorted(copies)
    }

    /// Offline copies keep what the search returned.
    func withDetails(_ copies: [MediaCopy]) async -> [MediaCopy] {
        let registry = sessionManager.registry
        let ready = registry.readyServers
        let details = await withTaskGroup(of: (MediaIdentity, MediaCopyDetails).self) { group in
            for copy in copies where ready.contains(copy.server) {
                guard let detail = registry.services(for: copy.server)?.detail else { continue }
                group.addTask { await (copy.id, MediaCopyDetails.load(for: copy.media, detail: detail)) }
            }
            var details: [MediaIdentity: MediaCopyDetails] = [:]
            for await (id, value) in group {
                details[id] = value
            }
            return details
        }
        return MediaCopy.sorted(copies.map { copy in
            var copy = copy
            copy.details = details[copy.id] ?? copy.details
            return copy
        })
    }
}

/// What tells copies of a title apart: their library, and the quality of their best version. Search results carry
/// neither the library on Jellyfin nor the dynamic range, so both are fetched for the copies only.
struct MediaCopyDetails: Hashable {
    var libraryID: String?
    /// E.g. `4K DV`.
    var qualityLabel: String?
    var bitrateText: String?

    static func load(for media: MediaItem, detail: any MediaDetailService) async -> MediaCopyDetails {
        let libraryID = if let id = media.librarySectionID {
            id
        } else {
            try? await detail.libraryID(for: media)
        }
        // A series has no file of its own.
        let versions = media.type == .series ? [] : await (try? detail.fileInfo(for: media))?.versions ?? []
        return MediaCopyDetails(libraryID: libraryID, versions: versions)
    }

    init(libraryID: String? = nil, versions: [MediaFileVersion] = []) {
        self.libraryID = libraryID
        let best = Self.bestVersion(of: versions)
        qualityLabel = best?.shortLabel
        bitrateText = best?.bitrateText
    }

    /// Highest resolution first, then the highest bitrate, which tells a remux from an encode.
    static func bestVersion(of versions: [MediaFileVersion]) -> MediaFileVersion? {
        let candidates = versions.contains(where: \.isAvailable) ? versions.filter(\.isAvailable) : versions
        return candidates.max { lhs, rhs in
            let lhsHeight = Int(lhs.signatureComponents.height) ?? 0
            let rhsHeight = Int(rhs.signatureComponents.height) ?? 0
            if lhsHeight != rhsHeight {
                return lhsHeight < rhsHeight
            }
            return (lhs.bitrateKbps ?? 0) < (rhs.bitrateKbps ?? 0)
        }
    }

    /// The copy's library, otherwise its quality, otherwise its title.
    func title(for media: MediaItem, libraryStore: LibraryStore) -> String {
        libraryTitle(for: media, libraryStore: libraryStore)
            ?? qualityLabel
            ?? media.playbackResolutionLabel
            ?? media.title
    }

    /// Quality and bitrate under a library title; nothing more when the title already is the quality.
    func subtitle(for media: MediaItem, libraryStore: LibraryStore) -> String? {
        guard libraryTitle(for: media, libraryStore: libraryStore) != nil else { return bitrateText }
        let parts = [qualityLabel ?? media.playbackResolutionLabel, bitrateText].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func libraryTitle(for media: MediaItem, libraryStore: LibraryStore) -> String? {
        if let title = media.librarySectionTitle {
            return title
        }
        guard let libraryID = media.librarySectionID ?? libraryID else { return nil }
        return libraryStore.library(LibraryIdentity(server: media.identity.server, libraryID: libraryID))?.title
    }
}

/// Shown when the displayed copy's server is offline and another copy is reachable: plays that copy instead.
struct ReachableCopyPlayButton: View {
    @Environment(ServerRegistry.self) private var registry
    let viewModel: MediaDetailViewModel
    let presenter: any PlaybackPresenting

    var body: some View {
        if let copy = viewModel.reachableCopyReplacingUnavailableServer,
           let services = registry.services(for: copy.server)
        {
            Button {
                Task {
                    await PlaybackLauncher(services: services, coordinator: presenter)
                        .play(ratingKey: copy.media.id, type: copy.media.type)
                }
            } label: {
                Label(String(localized: "media.availableOn.play \(copy.serverName)"), systemImage: "play.fill")
            }
            .actionButtonStyle(.primary)
        }
    }
}
