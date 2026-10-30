import CoreGraphics
import Foundation

enum VideoZoom: Hashable, Sendable {
    case fit
    case fill
    /// A scale relative to the fitted picture.
    case custom(Double)

    static let snapTolerance = 0.06
    static let stepScale = 0.05
    private static let maximumScaleFloor = 2.0

    init(_ mode: PlayerVideoScaleMode) {
        switch mode {
        case .fit: self = .fit
        case .fill: self = .fill
        }
    }

    var persistedMode: PlayerVideoScaleMode? {
        switch self {
        case .fit: .fit
        case .fill: .fill
        case .custom: nil
        }
    }

    static func fillScale(video: CGSize?, container: CGSize) -> Double {
        guard let video, video.width > 0, video.height > 0, container.width > 0, container.height > 0 else {
            return 1
        }
        let widthScale = container.width / video.width
        let heightScale = container.height / video.height
        return max(widthScale, heightScale) / min(widthScale, heightScale)
    }

    static func maximumScale(fillScale: Double) -> Double {
        max(fillScale * 1.5, maximumScaleFloor)
    }

    func scale(fillScale: Double) -> Double {
        switch self {
        case .fit: 1
        case .fill: fillScale
        case let .custom(scale): min(max(scale, 1), Self.maximumScale(fillScale: fillScale))
        }
    }

    /// Settles a free scale on fit or fill when it lands close to one of them.
    static func snapped(scale: Double, fillScale: Double) -> VideoZoom {
        if abs(scale - 1) <= snapTolerance {
            return .fit
        }
        if abs(scale / fillScale - 1) <= snapTolerance {
            return .fill
        }
        return .custom(scale)
    }

    /// The zoom one step away, on a 5% grid that also stops on fill so it is never stepped over.
    func stepped(by direction: Int, fillScale: Double) -> VideoZoom {
        let current = scale(fillScale: fillScale)
        let position = current / Self.stepScale
        let tolerance = 0.001
        let gridIndex = direction > 0
            ? (position + tolerance).rounded(.down) + 1
            : (position - tolerance).rounded(.up) - 1
        var next = gridIndex * Self.stepScale
        let isFillBetween = min(current, next) + tolerance < fillScale && fillScale < max(current, next) - tolerance
        if fillScale > 1 + tolerance, isFillBetween {
            next = fillScale
        }
        next = min(max(next, 1), Self.maximumScale(fillScale: fillScale))

        if abs(next - 1) < tolerance {
            return .fit
        }
        if abs(next - fillScale) < tolerance {
            return .fill
        }
        return .custom(next)
    }

    /// A custom zoom frames one show's picture (such as bars burned into a whole season), so it carries over
    /// between items of the same show and falls back to the remembered mode otherwise.
    static func carriedOver(
        _ zoom: VideoZoom,
        from previousContext: String?,
        to context: String?,
        persistedMode: PlayerVideoScaleMode,
    ) -> VideoZoom {
        if case .custom = zoom, let context, context == previousContext {
            return zoom
        }
        return VideoZoom(persistedMode)
    }

    func feedbackTitle(fillScale: Double) -> String {
        switch self {
        case .fit: PlayerVideoScaleMode.fit.feedbackTitle
        case .fill: PlayerVideoScaleMode.fill.feedbackTitle
        case .custom: Self.percentText(scale: scale(fillScale: fillScale))
        }
    }

    var feedbackSystemImage: String {
        switch self {
        case .fit: PlayerVideoScaleMode.fit.feedbackSystemImage
        case .fill, .custom: PlayerVideoScaleMode.fill.feedbackSystemImage
        }
    }

    static func percentText(scale: Double) -> String {
        String(localized: "player.feedback.videoScale.custom \(Int((scale * 100).rounded()))")
    }
}
