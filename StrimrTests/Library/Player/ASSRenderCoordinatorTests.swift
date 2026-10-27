@testable import Strimr
import Testing

struct ASSPresentationClockTests {
    @Test func `the presented clock wins between published ticks`() {
        let seconds = ASSPresentationClock.sourceSeconds(presented: 12.34, published: 12.25, followsPicture: true)

        #expect(seconds == 12.34)
    }

    @Test func `the published clock is used without a presented clock`() {
        let seconds = ASSPresentationClock.sourceSeconds(presented: nil, published: 12.25, followsPicture: true)

        #expect(seconds == 12.25)
    }

    @Test func `the published clock holds the picture during a seek`() {
        let seconds = ASSPresentationClock.sourceSeconds(presented: 300, published: 12.25, followsPicture: false)

        #expect(seconds == 12.25)
    }

    @Test func `a presented clock far from the published one is ignored`() {
        let seconds = ASSPresentationClock.sourceSeconds(presented: 0, published: 600, followsPicture: true)

        #expect(seconds == 600)
    }
}
