import CoreGraphics

enum PlayerHingeState: Equatable {
    case unavailable
    case closed
    case partiallyOpen
    case fullyOpen
}

/// How the player shares its space. On a foldable propped up like a laptop, the video takes the upright half and
/// the controls the half lying flat, so nothing is drawn over the picture and nothing interactive sits on the fold.
enum PlayerLayoutMode: Equatable {
    case fullScreen
    /// Frames are in the player's coordinate space.
    case tabletop(videoFrame: CGRect, controlsFrame: CGRect)

    var isTabletop: Bool {
        if case .tabletop = self {
            true
        } else {
            false
        }
    }

    static let minimumFoldCoverage: CGFloat = 0.9
    static let minimumHalfHeight: CGFloat = 120

    /// `divisions` are the frames of the active division regions (the fold) in the player's coordinate space.
    static func resolve(
        hinge: PlayerHingeState,
        divisions: [CGRect],
        containerSize: CGSize,
        isPictureInPictureActive: Bool,
    ) -> PlayerLayoutMode {
        guard hinge == .partiallyOpen,
              !isPictureInPictureActive,
              containerSize.width > 0,
              containerSize.height > 0,
              let fold = divisions.first(where: { isHorizontalFold($0, in: containerSize) })
        else {
            return .fullScreen
        }

        let videoFrame = CGRect(x: 0, y: 0, width: containerSize.width, height: fold.minY)
        let controlsFrame = CGRect(
            x: 0,
            y: fold.maxY,
            width: containerSize.width,
            height: containerSize.height - fold.maxY,
        )
        guard videoFrame.height >= minimumHalfHeight, controlsFrame.height >= minimumHalfHeight else {
            return .fullScreen
        }
        return .tabletop(videoFrame: videoFrame, controlsFrame: controlsFrame)
    }

    private static func isHorizontalFold(_ region: CGRect, in containerSize: CGSize) -> Bool {
        guard region.minY >= 0, region.maxY <= containerSize.height else { return false }
        let coveredWidth = min(region.maxX, containerSize.width) - max(region.minX, 0)
        return coveredWidth > region.height && coveredWidth >= containerSize.width * minimumFoldCoverage
    }
}
