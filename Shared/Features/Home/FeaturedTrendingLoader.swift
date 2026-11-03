import Foundation

/// Seerr's trending titles that are in the profile's libraries, as hero candidates.
@MainActor
struct FeaturedTrendingLoader {
    let baseURL: URL
    let aggregation: AggregationService

    static let pageCount = 5
    static let matchLimit = 5
    private static let batchSize = 3

    func candidates(sessions: [ServerSession], hiddenLibraryIDs: [ServerIdentity: Set<String>]) async
        -> [FeaturedCandidate]
    {
        let titles = await availableTitles()
        guard !titles.isEmpty, !sessions.isEmpty else { return [] }
        var candidates: [FeaturedCandidate] = []
        var matchedTitles = 0
        var start = 0
        while matchedTitles < Self.matchLimit, start < titles.count, !Task.isCancelled {
            let batch = titles[start ..< min(start + Self.batchSize, titles.count)]
            start += Self.batchSize
            let results = await withTaskGroup(of: (Int, [FeaturedCandidate]).self) { group in
                for (offset, title) in batch.enumerated() {
                    group.addTask { @MainActor in
                        await (offset, copies(of: title, sessions: sessions, hiddenLibraryIDs: hiddenLibraryIDs))
                    }
                }
                var values: [(Int, [FeaturedCandidate])] = []
                for await value in group {
                    values.append(value)
                }
                return values.sorted { $0.0 < $1.0 }.map(\.1)
            }
            for copies in results where !copies.isEmpty && matchedTitles < Self.matchLimit {
                candidates += copies
                matchedTitles += 1
            }
        }
        return candidates
    }

    /// Only titles Seerr marks available: the others are in no library it knows of.
    private func availableTitles() async -> [SeerrMedia] {
        let repository = SeerrDiscoverRepository(baseURL: baseURL)
        var titles: [SeerrMedia] = []
        for page in 1 ... Self.pageCount {
            do {
                let response = try await repository.getTrending(page: page)
                titles += response.results.filter(Self.isAvailable)
                if page >= response.totalPages {
                    break
                }
            } catch {
                if !Task.isCancelled, !error.isCancellation {
                    ErrorReporter.capture(error)
                }
                break
            }
        }
        return titles
    }

    static func isAvailable(_ media: SeerrMedia) -> Bool {
        guard media.mediaType == .movie || media.mediaType == .tv else { return false }
        switch media.mediaInfo?.status {
        case .available, .partiallyAvailable: return true
        default: return false
        }
    }

    static func descriptor(of media: SeerrMedia) -> MediaMatchDescriptor {
        MediaMatchDescriptor(
            kind: media.mediaType == .movie ? .movie : .series,
            guid: nil,
            externalIDs: ExternalIDs(tmdb: String(media.id)),
        )
    }

    /// The server linked to Seerr gives the item's id directly; the others are searched by title, keeping only the
    /// results whose ids match, as for the copies of a title (`MediaCopyFinder`).
    private func copies(
        of media: SeerrMedia,
        sessions: [ServerSession],
        hiddenLibraryIDs: [ServerIdentity: Set<String>],
    ) async -> [FeaturedCandidate] {
        let descriptor = Self.descriptor(of: media)
        let kind: MediaKind = media.mediaType == .movie ? .movie : .series
        let linked = linkedServer(of: media, sessions: sessions)
        let result = await aggregation.fanOut(servers: sessions) { services in
            if services.identity == linked?.server, let id = linked?.itemID {
                do {
                    return try await [services.detail.mediaItem(id: id)]
                } catch {
                    // A stale id falls back to the search below.
                    if Task.isCancelled || error.isCancellation {
                        throw error
                    }
                }
            }
            let title = media.title ?? media.name ?? ""
            guard !title.isEmpty else { return [] }
            return try await services.search.search(query: title, kinds: [kind]).compactMap(\.playableItem)
        }
        return sessions.compactMap { session -> FeaturedCandidate? in
            let hidden = hiddenLibraryIDs[session.identity] ?? []
            let item = (result.value[session.identity] ?? []).first { item in
                item.type == kind
                    && (item.identity == linked.map { MediaIdentity(server: $0.server, itemID: $0.itemID) }
                        || MediaMatching.matches(item.matchDescriptor, descriptor))
                    && !(item.librarySectionID.map(hidden.contains) ?? false)
            }
            return item.map { FeaturedCandidate(item: $0, reason: .trending) }
        }
    }

    private func linkedServer(of media: SeerrMedia, sessions: [ServerSession])
        -> (server: ServerIdentity, itemID: String)?
    {
        guard let info = media.mediaInfo else { return nil }
        if let ratingKey = info.ratingKey, let url = info.mediaUrl,
           let session = sessions.first(where: { $0.identity.provider == .plex && url.contains($0.identity.id) })
        {
            return (session.identity, ratingKey)
        }
        // Seerr does not say which Jellyfin server it is linked to, so the id is only trusted with a single one.
        let jellyfinSessions = sessions.filter { $0.identity.provider == .jellyfin }
        if let jellyfinID = info.jellyfinMediaId, jellyfinSessions.count == 1, let session = jellyfinSessions.first {
            return (session.identity, jellyfinID)
        }
        return nil
    }
}
