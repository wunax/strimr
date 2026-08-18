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

    func isSpoilerProtected(at level: SpoilerProtectionLevel) -> Bool {
        type == .episode && !isFullyWatched && level != .off
    }

    func shouldHideSpoilerSummary(at level: SpoilerProtectionLevel) -> Bool {
        isSpoilerProtected(at: level) && level == .full
    }

    func spoilerProtectedArtworkPath(at level: SpoilerProtectionLevel) -> String? {
        guard isSpoilerProtected(at: level) else { return nil }
        return grandparentArtPath ?? grandparentThumbPath
    }
}
