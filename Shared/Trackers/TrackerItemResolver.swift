import Foundation

/// Turns server items into what trackers can address. Series ids are cached so back-to-back episodes do not refetch
/// them; an item with no external id is never sent, because matching on a title alone could mark the wrong one.
@MainActor
final class TrackerItemResolver {
    private var seriesCache: [MediaIdentity: MediaItem] = [:]

    func resolve(_ media: MediaItem, detail: any MediaDetailService) async throws -> TrackerItem? {
        switch media.type {
        case .movie:
            let movie = media.externalIDs.isEmpty ? try await detail.mediaItem(id: media.id) : media
            guard !movie.externalIDs.isEmpty else { return nil }
            return TrackerItem(kind: .movie, ids: movie.externalIDs, title: movie.title, year: movie.year)
        case .episode:
            guard let seriesID = media.grandparentRatingKey,
                  let season = media.parentIndex,
                  let episode = media.index
            else { return nil }
            let series = try await series(id: seriesID, server: media.identity.server, detail: detail)
            guard !series.externalIDs.isEmpty else { return nil }
            return TrackerItem(
                kind: .episode,
                ids: series.externalIDs,
                title: series.title,
                year: series.year,
                season: season,
                episode: episode,
            )
        default:
            return nil
        }
    }

    /// A season or a series stands for its episodes on the server.
    func expand(_ media: MediaItem, detail: any MediaDetailService) async throws -> [MediaItem] {
        switch media.type {
        case .movie, .episode:
            return [media]
        case .season:
            return try await detail.episodes(for: media, seriesID: media.parentRatingKey)
        case .series:
            var episodes: [MediaItem] = []
            for season in try await detail.seasons(for: media) {
                try await episodes += detail.episodes(for: season, seriesID: media.id)
            }
            return episodes
        default:
            return []
        }
    }

    private func series(id: String, server: ServerIdentity, detail: any MediaDetailService) async throws -> MediaItem {
        let identity = MediaIdentity(server: server, itemID: id)
        if let cached = seriesCache[identity] {
            return cached
        }
        let series = try await detail.mediaItem(id: id)
        seriesCache[identity] = series
        return series
    }
}
