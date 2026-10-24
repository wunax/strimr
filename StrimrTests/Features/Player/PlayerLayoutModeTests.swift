import CoreGraphics
@testable import Strimr
import Testing

struct PlayerLayoutModeTests {
    private let container = CGSize(width: 800, height: 1000)
    private let horizontalFold = CGRect(x: 0, y: 490, width: 800, height: 20)

    private func resolve(
        hinge: PlayerHingeState = .partiallyOpen,
        divisions: [CGRect],
        containerSize: CGSize? = nil,
        isPictureInPictureActive: Bool = false,
    ) -> PlayerLayoutMode {
        PlayerLayoutMode.resolve(
            hinge: hinge,
            divisions: divisions,
            containerSize: containerSize ?? container,
            isPictureInPictureActive: isPictureInPictureActive,
        )
    }

    @Test func `a horizontal fold splits the video above and the controls below`() {
        #expect(resolve(divisions: [horizontalFold]) == .tabletop(
            videoFrame: CGRect(x: 0, y: 0, width: 800, height: 490),
            controlsFrame: CGRect(x: 0, y: 510, width: 800, height: 490),
        ))
    }

    @Test func `a fold without thickness still splits the player`() {
        let line = CGRect(x: 0, y: 500, width: 800, height: 0)

        #expect(resolve(divisions: [line]) == .tabletop(
            videoFrame: CGRect(x: 0, y: 0, width: 800, height: 500),
            controlsFrame: CGRect(x: 0, y: 500, width: 800, height: 500),
        ))
    }

    @Test(arguments: [PlayerHingeState.unavailable, .closed, .fullyOpen])
    func `only a partially open hinge splits the player`(hinge: PlayerHingeState) {
        #expect(resolve(hinge: hinge, divisions: [horizontalFold]) == .fullScreen)
    }

    @Test func `no active fold keeps the full screen`() {
        #expect(resolve(divisions: []) == .fullScreen)
    }

    @Test func `a vertical fold held like a book keeps the full screen`() {
        let verticalFold = CGRect(x: 390, y: 0, width: 20, height: 1000)

        #expect(resolve(divisions: [verticalFold]) == .fullScreen)
    }

    @Test func `picture in picture keeps the full screen`() {
        #expect(resolve(divisions: [horizontalFold], isPictureInPictureActive: true) == .fullScreen)
    }

    @Test func `a fold crossing only part of the player keeps the full screen`() {
        let partialFold = CGRect(x: 0, y: 490, width: 400, height: 20)

        #expect(resolve(divisions: [partialFold]) == .fullScreen)
    }

    @Test func `a fold outside the player keeps the full screen`() {
        let foldBelow = CGRect(x: 0, y: 1200, width: 800, height: 20)

        #expect(resolve(divisions: [foldBelow]) == .fullScreen)
    }

    @Test func `a fold leaving too little room on one side keeps the full screen`() {
        let foldNearBottom = CGRect(x: 0, y: 900, width: 800, height: 20)

        #expect(resolve(divisions: [foldNearBottom]) == .fullScreen)
    }

    @Test func `the horizontal fold is picked among several regions`() {
        let verticalFold = CGRect(x: 390, y: 0, width: 20, height: 1000)

        #expect(resolve(divisions: [verticalFold, horizontalFold]) == .tabletop(
            videoFrame: CGRect(x: 0, y: 0, width: 800, height: 490),
            controlsFrame: CGRect(x: 0, y: 510, width: 800, height: 490),
        ))
    }

    @Test func `a fold left over from the previous orientation keeps the full screen`() {
        let landscape = CGSize(width: 951, height: 553)
        let staleFold = CGRect(x: 0, y: 373.5, width: 669, height: 40)

        #expect(resolve(divisions: [staleFold], containerSize: landscape) == .fullScreen)
    }

    @Test func `an unmeasured player keeps the full screen`() {
        #expect(resolve(divisions: [horizontalFold], containerSize: .zero) == .fullScreen)
    }
}
