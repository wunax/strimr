import Foundation

extension MediaItem {
    var isFullyWatched: Bool {
        switch type {
        case .movie, .episode:
            return (viewCount ?? 0) > 0
        case .show, .season:
            guard let leafCount, let viewedLeafCount, leafCount > 0 else {
                return false
            }
            return leafCount == viewedLeafCount
        case .unknown:
            return false
        }
    }

    var remainingUnwatchedLeaves: Int? {
        guard [.show, .season].contains(type),
              let leafCount,
              let viewedLeafCount
        else {
            return nil
        }

        let remaining = leafCount - viewedLeafCount
        return remaining > 0 ? remaining : nil
    }
}
