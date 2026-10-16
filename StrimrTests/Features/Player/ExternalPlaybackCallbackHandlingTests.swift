import Foundation
@testable import Strimr
import Testing

struct ExternalPlaybackCallbackHandlingTests {
    private let item = MediaIdentity(server: ServerIdentity(provider: .plex, id: "server-1"), itemID: "item-1")

    private func update(
        position: TimeInterval?,
        progress: Double? = nil,
        duration: TimeInterval? = nil,
    ) -> ExternalPlaybackProgressUpdate? {
        ExternalPlaybackCallback(
            item: item,
            duration: duration,
            outcome: .finished(position: position, progress: progress),
        ).progressUpdate
    }

    @Test func `reported progress past the threshold marks the item watched`() {
        #expect(update(position: 3300, progress: 0.9167) == .watched)
        #expect(update(position: 3600, progress: 1) == .watched)
    }

    @Test func `known duration is used when the player sends no progress`() {
        #expect(update(position: 3300, duration: 3600) == .watched)
        #expect(update(position: 1200, duration: 3600) == .position(1200, duration: 3600))
    }

    @Test func `duration is derived from the progress when unknown`() {
        #expect(update(position: 1200, progress: 0.5) == .position(1200, duration: 2400))
    }

    @Test func `position without any duration is still pushed`() {
        #expect(update(position: 1200) == .position(1200, duration: nil))
    }

    @Test func `nothing is pushed without a position or at the start`() {
        #expect(update(position: nil, duration: 3600) == nil)
        #expect(update(position: 0, progress: 0, duration: 3600) == nil)
    }

    @Test func `a failure pushes nothing`() {
        let callback = ExternalPlaybackCallback(item: item, duration: 3600, outcome: .failed(message: nil))

        #expect(callback.progressUpdate == nil)
    }
}
