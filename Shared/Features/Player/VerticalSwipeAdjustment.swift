import CoreGraphics

enum VerticalSwipeAdjustment: Equatable {
    case brightness
    case volume

    /// Keeps drags that start near the top or bottom edge for Notification Center, Control Center and the
    /// home indicator.
    static let systemEdgeMargin: CGFloat = 44

    /// Only a mostly vertical drag that starts on the left or right third adjusts a level, so the center keeps
    /// its swipe up to the info panel.
    init?(start: CGPoint, translation: CGSize, area: CGSize) {
        guard area.height > Self.systemEdgeMargin * 2,
              start.y >= Self.systemEdgeMargin,
              start.y <= area.height - Self.systemEdgeMargin,
              abs(translation.height) > abs(translation.width)
        else { return nil }

        switch DoubleTapSeekZone(x: start.x, width: area.width) {
        case .backward: self = .brightness
        case .forward: self = .volume
        case .center: return nil
        }
    }

    /// Swiping up across most of the area goes from the lowest to the highest level.
    static func level(from startLevel: Double, translation: CGFloat, height: CGFloat) -> Double {
        let travel = max(Double(height) * 0.7, 200)
        return min(max(startLevel - Double(translation) / travel, 0), 1)
    }
}
