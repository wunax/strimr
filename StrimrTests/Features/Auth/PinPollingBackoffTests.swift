@testable import Strimr
import Testing

struct PinPollingBackoffTests {
    @Test func `polling starts at the base interval`() {
        #expect(PinPollingBackoff().interval == .seconds(2))
    }

    @Test func `rate limits double the interval up to the cap`() {
        var backoff = PinPollingBackoff()
        var intervals: [Duration] = []
        for _ in 0 ..< 4 {
            backoff.recordRateLimit()
            intervals.append(backoff.interval)
        }

        #expect(intervals == [.seconds(4), .seconds(8), .seconds(10), .seconds(10)])
    }

    @Test func `a response after a rate limit restores the base interval`() {
        var backoff = PinPollingBackoff()
        backoff.recordRateLimit()
        backoff.recordRateLimit()

        backoff.recordResponse()

        #expect(backoff.interval == .seconds(2))
    }
}
