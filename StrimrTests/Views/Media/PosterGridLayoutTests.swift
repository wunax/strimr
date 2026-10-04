import CoreGraphics
@testable import Strimr
import Testing

struct PosterGridLayoutTests {
    @Test(arguments: [
        (CGFloat(81), 4, CGFloat(83)),
        (112, 3, 115),
        (134, 2, 179),
    ])
    func `cards widen to fill an iPhone row`(targetWidth: CGFloat, columns: Int, cardWidth: CGFloat) {
        let layout = PosterGridLayout(availableWidth: 370, targetWidth: targetWidth, spacing: 12)

        #expect(layout.columnCount == columns)
        #expect(layout.cardWidth == cardWidth)
    }

    @Test func `unmeasured width falls back to the target`() {
        let layout = PosterGridLayout(availableWidth: 0, targetWidth: 112, spacing: 12)

        #expect(layout.columnCount == 1)
        #expect(layout.cardWidth == 112)
    }

    @Test func `width narrower than one card keeps a single column`() {
        let layout = PosterGridLayout(availableWidth: 90, targetWidth: 112, spacing: 12)

        #expect(layout.columnCount == 1)
        #expect(layout.cardWidth == 90)
    }
}
