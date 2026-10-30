import CoreGraphics
import SwiftAssRenderer

enum SubtitleGeometry {
    /// Applies the video's zoom, centered on the screen, to a rect laid out on the fitted picture.
    static func zoomed(_ rect: CGRect, by scale: Double, in container: CGSize) -> CGRect {
        guard scale != 1 else { return rect }
        return CGRect(
            x: container.width / 2 + (rect.minX - container.width / 2) * scale,
            y: container.height / 2 + (rect.minY - container.height / 2) * scale,
            width: rect.width * scale,
            height: rect.height * scale,
        )
    }

    /// Distance from the picture to each screen edge, negative where a zoom pushes the picture off screen.
    static func frameMargins(picture: CGRect, in container: CGSize) -> FrameMargins {
        FrameMargins(
            top: picture.minY,
            bottom: container.height - picture.maxY,
            left: picture.minX,
            right: container.width - picture.maxX,
        )
    }

    /// Dialogue is only laid out against the screen when the picture is cropped, so it never moves into the
    /// black bars of a fitted picture.
    static func cropsPicture(_ margins: FrameMargins) -> Bool {
        min(margins.top, margins.bottom, margins.left, margins.right) < -0.5
    }

    /// Moves bitmap subtitles that a zoom pushed off screen back inside `bounds`, without resizing them.
    ///
    /// Images in the same half of the screen move together, so the lines of one subtitle split into several
    /// images keep their spacing instead of piling up on the edge.
    static func keptVisible(_ frames: [CGRect], in bounds: CGRect) -> [CGRect] {
        let isLower = { (frame: CGRect) in frame.midY >= bounds.midY }
        let lift = frames.filter(isLower).map { $0.maxY - bounds.maxY }.max() ?? 0
        let drop = frames.filter { !isLower($0) }.map { bounds.minY - $0.minY }.max() ?? 0

        return frames.map { frame in
            var frame = frame
            frame.origin.y += isLower(frame) ? -max(lift, 0) : max(drop, 0)
            if frame.width > bounds.width {
                frame.origin.x = bounds.midX - frame.width / 2
            } else {
                frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
            }
            return frame
        }
    }
}
