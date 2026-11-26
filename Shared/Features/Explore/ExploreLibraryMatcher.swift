import Foundation

/// Where a catalog title sits in the profile's libraries.
struct ExploreLibraryMatch {
    var copies: [MediaCopy]
    /// Servers that did not answer: their absence proves nothing.
    var uncheckedServers: Int

    var isComplete: Bool {
        uncheckedServers == 0
    }
}

/// Finds a catalog title on the profile's servers. Each server is searched by title and a result only counts when its
/// ids match: the title alone never makes a copy.
@MainActor
final class ExploreLibraryMatcher {
    typealias Lookup = @MainActor (ExploreItem) async -> ExploreLibraryMatch

    static let negativeLifetime: TimeInterval = 10 * 60

    private struct Entry {
        let match: ExploreLibraryMatch
        let date: Date
        let scope: AnyHashable
    }

    private let lookup: Lookup
    /// What the answers depend on besides the title: a change drops the cached ones.
    private let scope: @MainActor () -> AnyHashable
    private let now: () -> Date
    private var cache: [String: Entry] = [:]

    init(
        lookup: @escaping Lookup,
        scope: @escaping @MainActor () -> AnyHashable,
        now: @escaping () -> Date = Date.init,
    ) {
        self.lookup = lookup
        self.scope = scope
        self.now = now
    }

    convenience init(sessionManager: SessionManager, settingsManager: SettingsManager) {
        self.init(
            lookup: { item in
                await Self.search(item, sessionManager: sessionManager, settingsManager: settingsManager)
            },
            scope: {
                let profileID = sessionManager.activeProfile?.id ?? ""
                return Self.scope(
                    servers: sessionManager.registry.sessions.filter(\.isEnabled).map(\.identity),
                    hiddenLibraries: settingsManager.libraryPreferences(profileID: profileID).hiddenLibraries,
                )
            },
        )
    }

    /// A complete answer with copies is kept for the session. An empty one expires, so a title added since is found,
    /// and an answer a server sat out is asked again next time. A change in the servers or the hidden libraries drops
    /// everything.
    func match(_ item: ExploreItem) async -> ExploreLibraryMatch {
        let key = Self.cacheKey(item)
        let currentScope = scope()
        if let entry = cache[key], entry.scope == currentScope, entry.match.isComplete {
            if !entry.match.copies.isEmpty || now().timeIntervalSince(entry.date) < Self.negativeLifetime {
                return entry.match
            }
        }
        let match = await lookup(item)
        cache[key] = Entry(match: match, date: now(), scope: currentScope)
        return match
    }

    static func scope(servers: [ServerIdentity], hiddenLibraries: [LibraryIdentity]) -> AnyHashable {
        AnyHashable([AnyHashable(Set(servers)), AnyHashable(Set(hiddenLibraries))])
    }

    func reset() {
        cache = [:]
    }

    /// The ids join the key, as a detail load can bring ids the rail version lacked.
    static func cacheKey(_ item: ExploreItem) -> String {
        let keys = item.matchDescriptor.matchKeys.sorted().joined(separator: ",")
        return "\(item.kind.rawValue)|\(keys)|\(item.title)|\(item.originalTitle ?? "")"
    }

    static func titles(of item: ExploreItem) -> [String] {
        var titles = [item.title]
        if let original = item.originalTitle, !original.isEmpty,
           original.localizedCaseInsensitiveCompare(item.title) != .orderedSame
        {
            titles.append(original)
        }
        return titles.filter { !$0.isEmpty }
    }

    static func matches(_ candidate: MediaItem, item: ExploreItem) -> Bool {
        candidate.type == item.kind.mediaKind && MediaMatching.matches(candidate.matchDescriptor, item.matchDescriptor)
    }

    private static func search(
        _ item: ExploreItem,
        sessionManager: SessionManager,
        settingsManager: SettingsManager,
    ) async -> ExploreLibraryMatch {
        guard !item.matchDescriptor.matchKeys.isEmpty else {
            return ExploreLibraryMatch(copies: [], uncheckedServers: 0)
        }
        let registry = sessionManager.registry
        let sessions = registry.sessions.filter(\.isEnabled)
        let profileID = sessionManager.activeProfile?.id ?? ""
        let hidden = settingsManager.libraryPreferences(profileID: profileID).hiddenLibraries
        let hiddenByServer = Dictionary(grouping: hidden, by: \.server).mapValues { Set($0.map(\.libraryID)) }
        let titles = titles(of: item)
        let result = await sessionManager.aggregation.fanOut(servers: sessions) { services -> [MediaItem] in
            var found: [MediaItem] = []
            var seen: Set<MediaIdentity> = []
            for title in titles {
                let results = try await services.search.search(query: title, kinds: [item.kind.mediaKind])
                for candidate in results.compactMap(\.playableItem) where matches(candidate, item: item) {
                    guard seen.insert(candidate.identity).inserted else { continue }
                    let hiddenIDs = hiddenByServer[services.identity] ?? []
                    if try await !FeaturedTrendingLoader.isInHiddenLibrary(
                        candidate,
                        hidden: hiddenIDs,
                        services: services,
                    ) {
                        found.append(candidate)
                    }
                }
            }
            return found
        }
        let copies = sessions.flatMap { session in
            (result.value[session.identity] ?? []).map {
                MediaCopy(media: $0, serverName: session.name, isReachable: true)
            }
        }
        return ExploreLibraryMatch(
            copies: MediaCopy.sorted(copies),
            uncheckedServers: result.failed.union(result.cancelled).union(result.skipped).count,
        )
    }
}
