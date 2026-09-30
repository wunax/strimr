import Foundation

/// Fetches and pins everything needed to display a download offline: the full item, its library and, for an
/// episode, the series with all its seasons and episodes. Pinning a new download is simply an enrichment run right
/// away; legacy downloads are enriched once their server is reachable again.
@MainActor
final class OfflineEnrichmentService {
    private struct SeriesContent {
        let series: MediaItem
        let seasons: [MediaItem]
        let episodes: [MediaItem]
    }

    private let store: OfflineStore
    /// Queuing a season enriches each episode; the series is only fetched once for all of them.
    private var seriesTasks: [String: Task<SeriesContent?, Error>] = [:]

    init(store: OfflineStore) {
        self.store = store
    }

    func enrich(download: DownloadItem, owner: MediaOwner, services: MediaServices) async -> DownloadEnrichmentState {
        do {
            let item = try await services.detail.mediaItem(id: download.itemID)
            let content = try await services.detail.details(for: item)
            let media = content.media
            store.store(detail: content, owner: owner)

            var pinnedItems = [media]
            var libraryAnchor = media
            if media.kind == .episode {
                let seriesID = media.grandparentRatingKey ?? content.parentSeries?.id
                if let seriesContent = try await seriesContent(
                    content: content,
                    seriesID: seriesID,
                    owner: owner,
                    services: services,
                ) {
                    pinnedItems.append(seriesContent.series)
                    pinnedItems.append(contentsOf: seriesContent.seasons)
                    pinnedItems.append(contentsOf: seriesContent.episodes)
                    libraryAnchor = seriesContent.series
                }
            }

            if let libraryID = try await services.detail.libraryID(for: libraryAnchor) {
                store.setLibraryID(libraryID, for: [media.id, libraryAnchor.id], owner: owner)
                if let library = try? await services.library.libraries().first(where: { $0.id == libraryID }) {
                    store.store(pinnedLibrary: library, owner: owner)
                }
            }

            store.pin(itemIDs: pinnedItems.map(\.id), downloadID: download.id, owner: owner)
            let artworkKeys = await pinArtwork(for: pinnedItems, primary: media, services: services)
            store.pin(itemIDs: [], artworkKeys: artworkKeys, downloadID: download.id, owner: owner)
            return .done
        } catch {
            guard !error.isCancellation else { return download.enrichmentState ?? .pending }
            if error.isNotFound {
                // Deleted on the server: the file stays playable with its minimal metadata.
                return .orphaned
            }
            if !error.isTransportFailure {
                ErrorReporter.capture(error)
            }
            return .pending
        }
    }

    /// Light refresh of an already enriched download (watch state and metadata) when coming back online.
    func refresh(download: DownloadItem, owner: MediaOwner, services: MediaServices) async {
        do {
            let item = try await services.detail.mediaItem(id: download.itemID)
            store.store(media: [item], owner: owner)
        } catch {
            guard !error.isCancellation, !error.isTransportFailure else { return }
            if error.isNotFound {
                return
            }
            ErrorReporter.capture(error)
        }
    }

    /// Poster and backdrop of the downloaded item, series and season posters, thumbnails of every episode.
    private func pinArtwork(for items: [MediaItem], primary: MediaItem, services: MediaServices) async -> [String] {
        guard let artwork = services.artwork as? CachedArtworkService else { return [] }
        var requests: [(path: String?, width: Int?, height: Int?)] = [
            (primary.thumbPath, nil, nil),
            (primary.preferredThumbPath, nil, nil),
            (primary.artPath, 1400, 800),
            (primary.grandparentArtPath, 1400, 800),
        ]
        for item in items where item.id != primary.id {
            switch item.kind {
            case .episode:
                requests.append((item.thumbPath, 640, 360))
            case .series:
                requests.append((item.thumbPath, nil, nil))
                requests.append((item.artPath, 1400, 800))
            default:
                requests.append((item.thumbPath, nil, nil))
            }
        }
        var keys: [String] = []
        var seen = Set<String>()
        for request in requests {
            guard !Task.isCancelled, let path = request.path else { continue }
            let key = CachedArtworkService.key(path: path, width: request.width, height: request.height)
            guard seen.insert(key).inserted else { continue }
            if let pinnedKey = await artwork.pin(path: path, width: request.width, height: request.height) {
                keys.append(pinnedKey)
            }
        }
        return keys
    }

    private func seriesContent(
        content: MediaDetailContent,
        seriesID: String?,
        owner: MediaOwner,
        services: MediaServices,
    ) async throws -> SeriesContent? {
        guard let seriesID = content.parentSeries?.id ?? seriesID else { return nil }
        let key = owner.id + "|" + seriesID
        if let task = seriesTasks[key] {
            return try await task.value
        }
        let store = store
        let task = Task<SeriesContent?, Error> {
            let series = if let parentSeries = content.parentSeries {
                parentSeries
            } else {
                try await services.detail.mediaItem(id: seriesID)
            }
            let seasons = try await services.detail.seasons(for: series)
            let episodes = try await services.detail.allEpisodes(for: series)
            store.store(media: [series] + seasons + episodes, owner: owner)
            return SeriesContent(series: series, seasons: seasons, episodes: episodes)
        }
        seriesTasks[key] = task
        do {
            let result = try await task.value
            // Keep the result briefly so the other episodes of a season download reuse it.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                self?.seriesTasks[key] = nil
            }
            return result
        } catch {
            seriesTasks[key] = nil
            throw error
        }
    }
}
