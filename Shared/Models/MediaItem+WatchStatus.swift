import Foundation

extension MediaItem {
    var isFullyWatched: Bool {
        switch type {
        case .movie, .episode:
            return (viewCount ?? 0) > 0
        case .series, .season:
            guard let leafCount, let viewedLeafCount, leafCount > 0 else {
                return false
            }
            return leafCount == viewedLeafCount
        case .collection, .playlist, .folder, .unknown:
            return false
        }
    }

    var remainingUnwatchedLeaves: Int? {
        guard [MediaKind.series, .season].contains(type),
              let leafCount,
              let viewedLeafCount
        else {
            return nil
        }

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
