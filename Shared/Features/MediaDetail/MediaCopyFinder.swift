import Foundation
import SwiftUI

/// Another copy of a title: on another server, or in another library of the same server.
struct MediaCopy: Identifiable, Hashable {
    let media: MediaItem
    let serverName: String
    /// Copies whose server is offline are listed greyed out.
    let isReachable: Bool

    var id: MediaIdentity {
        media.identity
    }

    var server: ServerIdentity {
        media.identity.server
    }

    var resolutionRank: Int {
        guard let value = media.videoResolution?.lowercased() else { return 0 }
        if value == "4k" || value == "uhd" {
            return 2160
        }
        if value == "sd" {
            return 480
        }
        return Int(value.filter(\.isNumber)) ?? 0
    }

    /// Resolution first, then library, then server.
    static func sorted(_ copies: [MediaCopy]) -> [MediaCopy] {
        copies.sorted { lhs, rhs in
            if lhs.resolutionRank != rhs.resolutionRank {
                return lhs.resolutionRank > rhs.resolutionRank
            }
            let lhsLibrary = lhs.media.librarySectionID ?? ""
            let rhsLibrary = rhs.media.librarySectionID ?? ""
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
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
        }
    }
}
