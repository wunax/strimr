import Foundation
@testable import Strimr
import Testing

@MainActor
struct PauseScreenPresentationTests {
    private let delay = Duration.milliseconds(100)

    private func makePresentation() -> PauseScreenPresentation {
        PauseScreenPresentation(delay: delay)
    }

    private func waitPastDelay() async throws {
        try await Task.sleep(for: delay * 3)
    }

    @Test func `staying eligible for the delay presents the pause screen`() async throws {
        let presentation = makePresentation()

        presentation.update(isEligible: true)
        #expect(!presentation.isPresented)

        try await waitPastDelay()
        #expect(presentation.isPresented)
    }

    @Test func `losing eligibility before the delay never presents`() async throws {
        let presentation = makePresentation()

        presentation.update(isEligible: true)
        presentation.update(isEligible: false)

        try await waitPastDelay()
        #expect(!presentation.isPresented)
    }

    @Test func `losing eligibility while presented dismisses`() async throws {
        let presentation = makePresentation()
        presentation.update(isEligible: true)
        try await waitPastDelay()

        presentation.update(isEligible: false)

        #expect(!presentation.isPresented)
    }

    @Test func `an interaction dismisses and presents again after another delay`() async throws {
        let presentation = makePresentation()
        presentation.update(isEligible: true)
        try await waitPastDelay()

        #expect(presentation.registerInteraction())
        #expect(!presentation.isPresented)

        try await waitPastDelay()
        #expect(presentation.isPresented)
    }

    @Test func `an interaction before the delay restarts the countdown`() async throws {
        let presentation = makePresentation()
        presentation.update(isEligible: true)

        try await Task.sleep(for: delay / 2)
        #expect(!presentation.registerInteraction())
        try await Task.sleep(for: delay / 2)
        #expect(!presentation.isPresented)

        try await waitPastDelay()
        #expect(presentation.isPresented)
    }

    @Test func `an interaction while ineligible starts nothing`() async throws {
        let presentation = makePresentation()

        #expect(!presentation.registerInteraction())

        try await waitPastDelay()
        #expect(!presentation.isPresented)
    }

    @Test func `cancelling dismisses and stops the countdown`() async throws {
        let presentation = makePresentation()
        presentation.update(isEligible: true)

        presentation.cancel()

        try await waitPastDelay()
        #expect(!presentation.isPresented)
    }
}
