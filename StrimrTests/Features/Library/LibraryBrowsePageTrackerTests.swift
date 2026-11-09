@testable import Strimr
import Testing

struct LibraryBrowsePageTrackerTests {
    @Test func `pages around an index cover two pages on each side`() {
        var tracker = LibraryBrowsePageTracker(pageSize: 40)

        let pages = tracker.pagesToLoad(around: 200, totalCount: 1000, isIndexLoaded: false)
        #expect(pages == [120, 160, 200, 240, 280])
    }

    @Test func `pages before the start and past the end are skipped`() {
        var tracker = LibraryBrowsePageTracker(pageSize: 40)

        let startPages = tracker.pagesToLoad(around: 10, totalCount: 1000, isIndexLoaded: false)
        #expect(startPages == [0, 40, 80])
        let endPages = tracker.pagesToLoad(around: 990, totalCount: 1000, isIndexLoaded: false)
        #expect(endPages == [880, 920, 960])
    }

    @Test func `an unknown total does not cut the last pages`() {
        var tracker = LibraryBrowsePageTracker(pageSize: 40)

        let pages = tracker.pagesToLoad(around: 0, totalCount: nil, isIndexLoaded: false)
        #expect(pages == [0, 40, 80])
    }

    @Test func `loaded and in-flight pages are not requested again`() {
        var tracker = LibraryBrowsePageTracker(pageSize: 40)
        let beganFirst = tracker.begin(0)
        #expect(beganFirst)
        tracker.finish(0, loaded: true)
        let beganSecond = tracker.begin(40)
        #expect(beganSecond)

        let beganLoadedAgain = tracker.begin(0)
        #expect(!beganLoadedAgain)
        let beganInFlightAgain = tracker.begin(40)
        #expect(!beganInFlightAgain)
        let pages = tracker.pagesToLoad(around: 0, totalCount: 1000, isIndexLoaded: true)
        #expect(pages == [80])
    }

    @Test func `a failed page can be requested again`() {
        var tracker = LibraryBrowsePageTracker(pageSize: 40)
        _ = tracker.begin(40)
        tracker.finish(40, loaded: false)

        let beganAgain = tracker.begin(40)
        #expect(beganAgain)
    }

    @Test func `a missing item reloads its page after a deletion`() {
        var tracker = LibraryBrowsePageTracker(pageSize: 40)
        _ = tracker.begin(0)
        tracker.finish(0, loaded: true)

        let pages = tracker.pagesToLoad(around: 39, totalCount: 40, isIndexLoaded: false)
        #expect(pages == [0])
    }

    @Test func `estimated total leaves room for one more page while pages come back full`() {
        #expect(LibraryBrowsePageTracker.estimatedTotal(current: 0, start: 0, received: 40, pageSize: 40) == 80)
        #expect(LibraryBrowsePageTracker.estimatedTotal(current: 80, start: 40, received: 40, pageSize: 40) == 120)
    }

    @Test func `estimated total stops at the last short page`() {
        #expect(LibraryBrowsePageTracker.estimatedTotal(current: 120, start: 80, received: 12, pageSize: 40) == 92)
        #expect(LibraryBrowsePageTracker.estimatedTotal(current: 80, start: 40, received: 0, pageSize: 40) == 40)
    }
}
