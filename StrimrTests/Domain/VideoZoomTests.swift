import CoreGraphics
@testable import Strimr
import Testing

struct VideoZoomTests {
    private let iPhone = CGSize(width: 874, height: 402)
    private let tv = CGSize(width: 1920, height: 1080)

    @Test func `fill scale crops the wide video onto a wider iPhone`() {
        let scale = VideoZoom.fillScale(video: CGSize(width: 1920, height: 1080), container: iPhone)

        #expect(abs(scale - (874.0 / 402.0) / (16.0 / 9.0)) < 0.0001)
    }

    @Test func `fill scale covers four by three and scope on a TV`() {
        let fourByThree = VideoZoom.fillScale(video: CGSize(width: 1440, height: 1080), container: tv)
        let scope = VideoZoom.fillScale(video: CGSize(width: 1920, height: 804), container: tv)

        #expect(abs(fourByThree - 4.0 / 3.0) < 0.0001)
        #expect(abs(scope - (1920.0 / 804.0) / (16.0 / 9.0)) < 0.0001)
    }

    @Test func `fill scale is neutral when the video matches the screen or is unknown`() {
        #expect(VideoZoom.fillScale(video: CGSize(width: 3840, height: 2160), container: tv) == 1)
        #expect(VideoZoom.fillScale(video: nil, container: tv) == 1)
        #expect(VideoZoom.fillScale(video: CGSize(width: 1920, height: 1080), container: .zero) == 1)
    }

    @Test func `maximum scale has a floor of two`() {
        #expect(VideoZoom.maximumScale(fillScale: 1) == 2)
        #expect(VideoZoom.maximumScale(fillScale: 1.22) == 2)
        #expect(abs(VideoZoom.maximumScale(fillScale: 1.6) - 2.4) < 0.0001)
    }

    @Test func `custom scale stays between fit and the maximum`() {
        #expect(VideoZoom.custom(0.5).scale(fillScale: 1.2) == 1)
        #expect(VideoZoom.custom(1.5).scale(fillScale: 1.2) == 1.5)
        #expect(VideoZoom.custom(5).scale(fillScale: 1.2) == 2)
        #expect(VideoZoom.fill.scale(fillScale: 1.2) == 1.2)
        #expect(VideoZoom.fit.scale(fillScale: 1.2) == 1)
    }

    @Test func `free scales settle on fit or fill when close`() {
        #expect(VideoZoom.snapped(scale: 1.04, fillScale: 1.22) == .fit)
        #expect(VideoZoom.snapped(scale: 1.25, fillScale: 1.22) == .fill)
        #expect(VideoZoom.snapped(scale: 1.6, fillScale: 1.22) == .custom(1.6))
        #expect(VideoZoom.snapped(scale: 1.12, fillScale: 1.4) == .custom(1.12))
    }

    @Test func `fit wins when fill matches the fitted picture`() {
        #expect(VideoZoom.snapped(scale: 1, fillScale: 1) == .fit)
    }

    @Test func `custom zoom carries over within the same show`() {
        let zoom = VideoZoom.carriedOver(.custom(1.33), from: "show", to: "show", persistedMode: .fill)

        #expect(zoom == .custom(1.33))
    }

    @Test func `custom zoom resets to the remembered mode for another show`() {
        #expect(VideoZoom.carriedOver(.custom(1.33), from: "show", to: "movie", persistedMode: .fill) == .fill)
        #expect(VideoZoom.carriedOver(.custom(1.33), from: nil, to: nil, persistedMode: .fit) == .fit)
    }

    @Test func `fit and fill follow the remembered mode`() {
        #expect(VideoZoom.carriedOver(.fit, from: "show", to: "show", persistedMode: .fill) == .fill)
    }

    @Test func `only fit and fill are remembered`() {
        #expect(VideoZoom.fit.persistedMode == .fit)
        #expect(VideoZoom.fill.persistedMode == .fill)
        #expect(VideoZoom.custom(1.5).persistedMode == nil)
    }
}
