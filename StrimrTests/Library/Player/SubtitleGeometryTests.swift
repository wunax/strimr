import CoreGraphics
@testable import Strimr
import SwiftAssRenderer
import Testing

struct SubtitleGeometryTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)

    @Test func `zoom scales a rect around the screen center`() {
        let rect = CGRect(x: 100, y: 50, width: 800, height: 400)

        #expect(SubtitleGeometry.zoomed(rect, by: 1.5, in: bounds.size) == CGRect(
            x: -100, y: -50, width: 1200, height: 600,
        ))
        #expect(SubtitleGeometry.zoomed(rect, by: 1, in: bounds.size) == rect)
    }

    @Test func `margins are positive around a fitted picture`() {
        let margins = SubtitleGeometry.frameMargins(
            picture: CGRect(x: 0, y: 40, width: 1000, height: 420),
            in: bounds.size,
        )

        #expect(margins == FrameMargins(top: 40, bottom: 40, left: 0, right: 0))
        #expect(!SubtitleGeometry.cropsPicture(margins))
    }

    @Test func `margins are negative where a zoom crops the picture`() {
        let margins = SubtitleGeometry.frameMargins(
            picture: CGRect(x: -100, y: -50, width: 1200, height: 600),
            in: bounds.size,
        )

        #expect(margins == FrameMargins(top: -50, bottom: -50, left: -100, right: -100))
        #expect(SubtitleGeometry.cropsPicture(margins))
    }

    @Test func `rounding noise does not count as cropping`() {
        #expect(!SubtitleGeometry.cropsPicture(FrameMargins(top: -0.2, bottom: 0, left: 0, right: 0)))
    }

    @Test func `frames already on screen stay in place`() {
        let frames = [CGRect(x: 300, y: 420, width: 400, height: 50)]

        #expect(SubtitleGeometry.keptVisible(frames, in: bounds) == frames)
    }

    @Test func `a frame past the bottom is lifted back on screen`() {
        let frames = [CGRect(x: 300, y: 480, width: 400, height: 50)]

        #expect(SubtitleGeometry.keptVisible(frames, in: bounds) == [CGRect(x: 300, y: 450, width: 400, height: 50)])
    }

    @Test func `a frame past the top is moved down on screen`() {
        let frames = [CGRect(x: 300, y: -20, width: 400, height: 50)]

        #expect(SubtitleGeometry.keptVisible(frames, in: bounds) == [CGRect(x: 300, y: 0, width: 400, height: 50)])
    }

    @Test func `lines of one subtitle move together`() {
        let frames = [
            CGRect(x: 300, y: 430, width: 400, height: 40),
            CGRect(x: 320, y: 480, width: 360, height: 40),
        ]

        #expect(SubtitleGeometry.keptVisible(frames, in: bounds) == [
            CGRect(x: 300, y: 410, width: 400, height: 40),
            CGRect(x: 320, y: 460, width: 360, height: 40),
        ])
    }

    @Test func `top and bottom subtitles move independently`() {
        let frames = [
            CGRect(x: 300, y: -10, width: 400, height: 40),
            CGRect(x: 300, y: 480, width: 400, height: 40),
        ]

        #expect(SubtitleGeometry.keptVisible(frames, in: bounds) == [
            CGRect(x: 300, y: 0, width: 400, height: 40),
            CGRect(x: 300, y: 460, width: 400, height: 40),
        ])
    }

    @Test func `frames are kept inside the sides and centered when wider than the screen`() {
        let frames = [
            CGRect(x: 900, y: 400, width: 300, height: 40),
            CGRect(x: -100, y: 300, width: 1200, height: 40),
        ]

        #expect(SubtitleGeometry.keptVisible(frames, in: bounds) == [
            CGRect(x: 700, y: 400, width: 300, height: 40),
            CGRect(x: -100, y: 300, width: 1200, height: 40),
        ])
    }
}
