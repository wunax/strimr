import Foundation
@testable import Strimr
import Testing

struct ProfilePromptOnReturnTests {
    private let backgroundedAt = Date(timeIntervalSince1970: 1_000_000)

    @Test func `prompts after a long absence`() {
        var prompt = ProfilePromptOnReturn()
        prompt.didEnterBackground(at: backgroundedAt)

        let prompts = prompt.shouldPrompt(
            at: returned(after: ProfilePromptOnReturn.absenceThreshold),
            isPlaybackActive: false,
        )
        #expect(prompts)
    }

    @Test func `does not prompt after a short absence`() {
        var prompt = ProfilePromptOnReturn()
        prompt.didEnterBackground(at: backgroundedAt)

        let prompts = prompt.shouldPrompt(at: returned(after: 60), isPlaybackActive: false)
        #expect(!prompts)
    }

    @Test func `does not prompt without having been in the background`() {
        var prompt = ProfilePromptOnReturn()

        let prompts = prompt.shouldPrompt(at: backgroundedAt, isPlaybackActive: false)
        #expect(!prompts)
    }

    @Test func `does not prompt while the player is shown`() {
        var prompt = ProfilePromptOnReturn()
        prompt.didEnterBackground(at: backgroundedAt)

        let prompts = prompt.shouldPrompt(at: returned(after: 3600), isPlaybackActive: true)
        #expect(!prompts)
    }

    @Test func `prompts only once per return`() {
        var prompt = ProfilePromptOnReturn()
        prompt.didEnterBackground(at: backgroundedAt)
        let date = returned(after: 3600)

        let first = prompt.shouldPrompt(at: date, isPlaybackActive: false)
        let second = prompt.shouldPrompt(at: date, isPlaybackActive: false)
        #expect(first)
        #expect(!second)
    }

    @Test func `a short absence does not leave a pending prompt`() {
        var prompt = ProfilePromptOnReturn()
        prompt.didEnterBackground(at: backgroundedAt)

        let first = prompt.shouldPrompt(at: returned(after: 60), isPlaybackActive: false)
        let second = prompt.shouldPrompt(at: returned(after: 3600), isPlaybackActive: false)
        #expect(!first)
        #expect(!second)
    }

    @Test func `a cancelled absence does not prompt`() {
        var prompt = ProfilePromptOnReturn()
        prompt.didEnterBackground(at: backgroundedAt)
        prompt.cancel()

        let prompts = prompt.shouldPrompt(at: returned(after: 3600), isPlaybackActive: false)
        #expect(!prompts)
    }

    private func returned(after interval: TimeInterval) -> Date {
        backgroundedAt.addingTimeInterval(interval)
    }
}
