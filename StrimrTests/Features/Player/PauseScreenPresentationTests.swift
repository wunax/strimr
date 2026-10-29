import Foundation
@testable import Strimr
import Testing

@MainActor
struct PauseScreenPresentationTests {
    private let delay = Duration.milliseconds(100)
    private let clock = TestClock()

    private func makePresentation() -> PauseScreenPresentation {
        PauseScreenPresentation(delay: delay, clock: clock)
    }

    private func waitPastDelay() async {
        await clock.advance(by: delay * 3)
    }

    @Test func `staying eligible for the delay presents the pause screen`() async {
        let presentation = makePresentation()

        presentation.update(isEligible: true)
        #expect(!presentation.isPresented)

        await waitPastDelay()
        #expect(presentation.isPresented)
    }

    @Test func `losing eligibility before the delay never presents`() async {
        let presentation = makePresentation()

        presentation.update(isEligible: true)
        presentation.update(isEligible: false)

        await waitPastDelay()
        #expect(!presentation.isPresented)
    }

    @Test func `losing eligibility while presented dismisses`() async {
        let presentation = makePresentation()
        presentation.update(isEligible: true)
        await waitPastDelay()

        presentation.update(isEligible: false)

        #expect(!presentation.isPresented)
    }

    @Test func `an interaction dismisses and presents again after another delay`() async {
        let presentation = makePresentation()
        presentation.update(isEligible: true)
        await waitPastDelay()

        #expect(presentation.registerInteraction())
        #expect(!presentation.isPresented)

        await waitPastDelay()
        #expect(presentation.isPresented)
    }

    @Test func `an interaction before the delay restarts the countdown`() async {
        let presentation = makePresentation()
        presentation.update(isEligible: true)

        await clock.advance(by: delay / 2)
        #expect(!presentation.registerInteraction())
        await clock.advance(by: delay / 2)
        #expect(!presentation.isPresented)

        await waitPastDelay()
        #expect(presentation.isPresented)
    }

    @Test func `an interaction while ineligible starts nothing`() async {
        let presentation = makePresentation()

        #expect(!presentation.registerInteraction())

        await waitPastDelay()
        #expect(!presentation.isPresented)
    }

    @Test func `cancelling dismisses and stops the countdown`() async {
        let presentation = makePresentation()
        presentation.update(isEligible: true)

        presentation.cancel()

        await waitPastDelay()
        #expect(!presentation.isPresented)
    }
}
