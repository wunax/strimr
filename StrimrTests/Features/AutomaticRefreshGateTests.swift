import Foundation
@testable import Strimr
import Testing

struct AutomaticRefreshGateTests {
    private func startedGate() -> AutomaticRefreshGate {
        var gate = AutomaticRefreshGate(debounceInterval: 90)
        _ = gate.startInitialLoadIfNeeded()
        return gate
    }

    @Test func `skips a refresh within the debounce window`() {
        var gate = startedGate()

        let shouldRefresh = gate.shouldRefresh(now: Date().addingTimeInterval(10), isLoading: false)

        #expect(!shouldRefresh)
    }

    @Test func `allows a refresh within the debounce window when ignoring the debounce`() {
        var gate = startedGate()

        let shouldRefresh = gate.shouldRefresh(
            now: Date().addingTimeInterval(10),
            isLoading: false,
            ignoringDebounce: true,
        )

        #expect(shouldRefresh)
    }

    @Test func `still skips a refresh while loading when ignoring the debounce`() {
        var gate = startedGate()

        let shouldRefresh = gate.shouldRefresh(
            now: Date().addingTimeInterval(10),
            isLoading: true,
            ignoringDebounce: true,
        )

        #expect(!shouldRefresh)
    }
}
