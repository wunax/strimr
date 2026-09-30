import AetherEngine
import Foundation

/// A downloaded file ready to be played by the local player.
struct LocalPlaybackRequest: Identifiable {
    let id = UUID()
    let media: MediaItem
    let url: URL
    let externalSubtitles: [ExternalSubtitleTrack]
    let owner: MediaOwner?
    let resumes: Bool
}

enum DownloadBadgeState: Equatable {
    case queued
    case downloading(progress: Double)
    case downloaded
    case failed
    case partial(downloaded: Int, total: Int?)
}

extension DownloadManager {
    func completedOwnedItem(for identity: MediaIdentity) -> DownloadItem? {
        guard let item = latestItem(for: identity), item.status == .completed,
              localVideoURL(for: item) != nil
        else { return nil }
        return item
    }

    /// Completed downloads of the active user that belong to a series or a season.
    func completedEpisodes(inContainer container: MediaItem) -> [DownloadItem] {
        ownedItems.filter { item in
            guard item.status == .completed,
                  item.identity?.server == container.identity.server,
                  item.metadata.type == .episode
            else { return false }
            switch container.kind {
            case .series:
                return item.metadata.grandparentRatingKey == container.id
            case .season:
                return item.metadata.parentRatingKey == container.id
            default:
                return false
            }
        }
    }

    private func activeEpisodes(inContainer container: MediaItem) -> [DownloadItem] {
        ownedItems.filter { item in
            guard item.status.isActive, item.identity?.server == container.identity.server else { return false }
            return container.kind == .series
                ? item.metadata.grandparentRatingKey == container.id
                : item.metadata.parentRatingKey == container.id
        }
    }

    func badgeState(for media: MediaDisplayItem) -> DownloadBadgeState? {
        guard let item = media.playableItem else { return nil }
        switch item.kind {
        case .series, .season:
            let downloaded = completedEpisodes(inContainer: item).count
            guard downloaded > 0 || !activeEpisodes(inContainer: item).isEmpty else { return nil }
            return .partial(downloaded: downloaded, total: item.leafCount)
        case .movie, .episode:
            guard let download = latestItem(for: item.identity) else { return nil }
            switch download.status {
            case .queued, .preparing:
                return .queued
            case .downloading:
                return .downloading(progress: download.progress)
            case .completed:
                return .downloaded
            case .failed:
                return .failed
            }
        case .clip, .collection, .playlist, .folder, .unknown:
            return nil
        }
    }

    /// Whether an item can be played or browsed to something playable without its server.
    func isAvailableOffline(_ media: MediaDisplayItem) -> Bool {
        guard let item = media.playableItem else { return false }
        switch item.kind {
        case .series, .season:
            return !completedEpisodes(inContainer: item).isEmpty
        default:
            return completedOwnedItem(for: item.identity) != nil
        }
    }

    func localPlaybackRequest(for item: DownloadItem, resumes: Bool = true) -> LocalPlaybackRequest? {
        guard let url = localVideoURL(for: item) else { return nil }
        return LocalPlaybackRequest(
            media: playbackMedia(for: item),
            url: url,
            externalSubtitles: localExternalSubtitles(for: item),
            owner: owner(of: item),
            resumes: resumes,
        )
    }

    /// Local playback for a movie or an episode, or for the next downloaded episode of a series or season.
    func localPlaybackRequest(
        for identity: MediaIdentity,
        kind: MediaKind,
        resumes: Bool = true,
    ) -> LocalPlaybackRequest? {
        switch kind {
        case .movie, .episode, .clip:
            return completedOwnedItem(for: identity).flatMap { localPlaybackRequest(for: $0, resumes: resumes) }
        case .series, .season:
            let episodes = ownedItems
                .filter { item in
                    item.status == .completed
                        && item.identity?.server == identity.server
                        && (kind == .series
                            ? item.metadata.grandparentRatingKey == identity.itemID
                            : item.metadata.parentRatingKey == identity.itemID)
                }
                .sorted(by: Self.episodeOrder)
            let next = episodes.first { !playbackMedia(for: $0).isFullyWatched } ?? episodes.first
            return next.flatMap { localPlaybackRequest(for: $0, resumes: resumes) }
        case .collection, .playlist, .folder, .unknown:
            return nil
        }
    }

    /// Next downloaded episode of the same series, used to chain local playback.
    func nextDownloadedEpisode(after media: MediaItem) -> DownloadItem? {
        guard media.kind == .episode, let seriesID = media.grandparentRatingKey else { return nil }
        let episodes = ownedItems
            .filter {
                $0.status == .completed
                    && $0.identity?.server == media.identity.server
                    && $0.metadata.grandparentRatingKey == seriesID
            }
            .sorted(by: Self.episodeOrder)
        guard let index = episodes.firstIndex(where: { $0.itemID == media.id }) else { return nil }
        return episodes.indices.contains(index + 1) ? episodes[index + 1] : nil
    }

    private static func episodeOrder(_ lhs: DownloadItem, _ rhs: DownloadItem) -> Bool {
        let lhsKey = (lhs.metadata.parentIndex ?? Int.max, lhs.metadata.index ?? Int.max)
        let rhsKey = (rhs.metadata.parentIndex ?? Int.max, rhs.metadata.index ?? Int.max)
        return lhsKey < rhsKey
    }
}

extension DownloadManager {
    /// Downloaded copy matching the detail page's play action: the target movie or episode, or for a series or
    /// season the next downloaded episode.
    func localPlaybackRequest(
        forDetail viewModel: MediaDetailViewModel,
        resumes: Bool = true,
    ) -> LocalPlaybackRequest? {
        if let item = viewModel.primaryActionItem, item.kind == .movie || item.kind == .episode,
           let request = localPlaybackRequest(for: item.identity, kind: item.kind, resumes: resumes)
        {
            return request
        }
        let media = viewModel.media.mediaItem
        guard media.kind == .series || media.kind == .season || media.kind == .movie || media.kind == .episode else {
            return nil
        }
        return localPlaybackRequest(for: media.identity, kind: media.kind, resumes: resumes)
    }
}
