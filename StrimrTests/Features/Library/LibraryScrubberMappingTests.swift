import Foundation
@testable import Strimr
import Testing

struct LibraryScrubberMappingTests {
    @Test func `track ends reach the first and last items`() {
        #expect(LibraryScrubberMapping.index(forFraction: 0, totalCount: 500) == 0)
        #expect(LibraryScrubberMapping.index(forFraction: 1, totalCount: 500) == 499)
        #expect(LibraryScrubberMapping.index(forFraction: 0.5, totalCount: 501) == 250)
    }

    @Test func `fractions outside the track are clamped`() {
        #expect(LibraryScrubberMapping.index(forFraction: -0.3, totalCount: 10) == 0)
        #expect(LibraryScrubberMapping.index(forFraction: 1.7, totalCount: 10) == 9)
    }

    @Test func `a single item always maps to the start`() {
        #expect(LibraryScrubberMapping.index(forFraction: 0.8, totalCount: 1) == 0)
        #expect(LibraryScrubberMapping.fraction(forIndex: 0, totalCount: 1) == 0)
    }

    @Test(arguments: [0, 1, 137, 998, 999])
    func `index and fraction round trip`(index: Int) {
        let fraction = LibraryScrubberMapping.fraction(forIndex: index, totalCount: 1000)

        #expect(LibraryScrubberMapping.index(forFraction: fraction, totalCount: 1000) == index)
    }

    @Test func `scroll offset maps to the track`() {
        #expect(LibraryScrubberMapping.fraction(contentOffset: 0, maximumOffset: 400) == 0)
        #expect(LibraryScrubberMapping.fraction(contentOffset: 100, maximumOffset: 400) == 0.25)
        #expect(LibraryScrubberMapping.fraction(contentOffset: 500, maximumOffset: 400) == 1)
        #expect(LibraryScrubberMapping.fraction(contentOffset: -40, maximumOffset: 400) == 0)
        #expect(LibraryScrubberMapping.fraction(contentOffset: 10, maximumOffset: 0) == 0)
    }

    @Test func `throttle lets one load through per interval`() {
        var throttle = LibraryScrubLoadThrottle(interval: .milliseconds(200))
        let start = ContinuousClock.now

        let first = throttle.shouldLoad(at: start)
        #expect(first)
        let tooSoon = throttle.shouldLoad(at: start.advanced(by: .milliseconds(50)))
        #expect(!tooSoon)
        let justBefore = throttle.shouldLoad(at: start.advanced(by: .milliseconds(199)))
        #expect(!justBefore)
        let afterInterval = throttle.shouldLoad(at: start.advanced(by: .milliseconds(200)))
        #expect(afterInterval)
    }

    @Test func `throttle reset allows a load right away`() {
        var throttle = LibraryScrubLoadThrottle(interval: .milliseconds(200))
        let start = ContinuousClock.now
        _ = throttle.shouldLoad(at: start)

        throttle.reset()

        let afterReset = throttle.shouldLoad(at: start.advanced(by: .milliseconds(10)))
        #expect(afterReset)
    }
}
