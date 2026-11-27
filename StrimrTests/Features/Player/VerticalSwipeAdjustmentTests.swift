import CoreGraphics
@testable import Strimr
import Testing

struct VerticalSwipeAdjustmentTests {
    private let area = CGSize(width: 900, height: 400)
    private let up = CGSize(width: 4, height: -30)

    @Test func `the left third adjusts brightness and the right third the volume`() {
        #expect(VerticalSwipeAdjustment(start: CGPoint(x: 100, y: 200), translation: up, area: area) == .brightness)
        #expect(VerticalSwipeAdjustment(start: CGPoint(x: 800, y: 200), translation: up, area: area) == .volume)
    }

    @Test func `the center keeps its own swipes`() {
        #expect(VerticalSwipeAdjustment(start: CGPoint(x: 450, y: 200), translation: up, area: area) == nil)
    }

    @Test func `horizontal drags are ignored`() {
        let sideways = CGSize(width: 40, height: -20)
        #expect(VerticalSwipeAdjustment(start: CGPoint(x: 100, y: 200), translation: sideways, area: area) == nil)
    }

    @Test(arguments: [10.0, 390.0])
    func `drags starting at the system edges are ignored`(y: Double) {
        #expect(VerticalSwipeAdjustment(start: CGPoint(x: 100, y: y), translation: up, area: area) == nil)
    }

    @Test func `swiping up raises the level and swiping down lowers it`() {
        #expect(VerticalSwipeAdjustment.level(from: 0.5, translation: -140, height: 400) > 0.5)
        #expect(VerticalSwipeAdjustment.level(from: 0.5, translation: 140, height: 400) < 0.5)
    }

    @Test func `the level stays between zero and one`() {
        #expect(VerticalSwipeAdjustment.level(from: 0.9, translation: -1000, height: 400) == 1)
        #expect(VerticalSwipeAdjustment.level(from: 0.1, translation: 1000, height: 400) == 0)
    }
}
