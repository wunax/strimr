import Foundation

extension MediaItem {
    var isFullyWatched: Bool {
        watchState.isPlayed
    }

    var remainingUnwatchedLeaves: Int? {
        guard [MediaKind.series, .season].contains(type) else { return nil }
        if let unplayedItemCount = watchState.unplayedItemCount {
            return unplayedItemCount > 0 ? unplayedItemCount : nil
        }

        guard let leafCount, let viewedLeafCount else { return nil }

        let remaining = leafCount - viewedLeafCount
        return remaining > 0 ? remaining : nil
    }

    var seasonProgress: EpisodeProgress? {
        guard type == .season else { return nil }
        if let leafCount, let viewedLeafCount, leafCount > 0 {
            return EpisodeProgress(watched: min(viewedLeafCount, leafCount), total: leafCount)
        }
        // Jellyfin leaves watched episodes out of a season's RecursiveItemCount, so its total is the ChildCount.
        if let childCount, childCount > 0, let unplayed = watchState.unplayedItemCount {
            return EpisodeProgress(watched: max(0, childCount - unplayed), total: childCount)
        }
        return nil
    }

    /// Progress a season chip shows: none for a season not started yet.
    var startedSeasonProgress: EpisodeProgress? {
        guard let seasonProgress, seasonProgress.watched > 0 else { return nil }
        return seasonProgress
    }

    func isSpoilerProtected(at level: SpoilerProtectionLevel) -> Bool {
        type == .episode && !isFullyWatched && level != .off
    }

    func shouldHideSpoilerSummary(at level: SpoilerProtectionLevel) -> Bool {
        isSpoilerProtected(at: level) && level == .full
    }

    /// The episode title stands in for the plot as much as the summary does, so full protection swaps it for the
    /// episode number.
    func spoilerSafeTitle(at level: SpoilerProtectionLevel) -> String {
        guard shouldHideSpoilerSummary(at: level) else { return title }
        guard let index else { return String(localized: "media.spoilerProtection.titleHidden") }
        return String(localized: "media.labels.episodeNumber \(String(index))")
    }

    func spoilerProtectedArtworkPath(at level: SpoilerProtectionLevel) -> String? {
        guard isSpoilerProtected(at: level) else { return nil }
        return seriesArtworkPath
    }

    var seriesArtworkPath: String? {
        grandparentArtPath ?? grandparentThumbPath
    }

    var seasonPosterPath: String? {
        parentThumbPath ?? grandparentThumbPath
    }
}

struct EpisodeProgress: Equatable {
    let watched: Int
    let total: Int

    var fraction: Double {
        Double(watched) / Double(total)
    }

    var isComplete: Bool {
        watched >= total
    }
}
