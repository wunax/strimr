import Foundation
@testable import Strimr
import Testing

struct DownloadActivityTests {
    private let server = ServerIdentity(provider: .plex, id: "server-1")

    private func episode(
        _ itemID: String,
        _ status: DownloadStatus,
        progress: Double? = nil,
        id: String? = nil,
        createdAt: TimeInterval = 0,
    ) -> DownloadItem {
        var item = DownloadItem.make(
            id: id ?? "download-\(itemID)",
            itemID: itemID,
            server: server,
            status: status,
            type: .episode,
            createdAt: Date(timeIntervalSince1970: createdAt),
        )
        if let progress {
            item.progress = progress
        }
        return item
    }

    @Test func `server preparation shows its own ring`() {
        let activity = DownloadActivity(item: episode("e1", .preparing, progress: 0.4))

        #expect(activity.phase == .preparing)
        #expect(activity.ring == .init(progress: 0.4, style: .serverPreparation))
    }

    @Test func `the transfer shows the plain ring`() {
        let activity = DownloadActivity(item: episode("e1", .downloading, progress: 0.7))

        #expect(activity.ring == .init(progress: 0.7, style: .transfer))
    }

    @Test(arguments: [DownloadStatus.preparing, .downloading])
    func `a phase without progress keeps the spinner`(status: DownloadStatus) {
        let activity = DownloadActivity(item: episode("e1", status, progress: 0))

        #expect(activity.ring == nil)
        #expect(activity.showsSpinner)
    }

    @Test func `a queued download shows neither ring nor spinner`() {
        let activity = DownloadActivity(item: episode("e1", .queued))

        #expect(activity.ring == nil)
        #expect(!activity.showsSpinner)
        #expect(activity.isInProgress)
    }

    @Test func `a paused download keeps its progress on the ring`() {
        let activity = DownloadActivity(item: episode("e1", .paused, progress: 0.4))

        #expect(activity.phase == .paused)
        #expect(!activity.isInProgress)
        #expect(activity.ring == .init(progress: 0.4, style: .transfer))
    }

    @Test func `a running episode takes precedence over a paused one`() throws {
        let activity = try #require(DownloadActivity(
            episodes: [episode("e1", .paused, progress: 0.5), episode("e2", .downloading, progress: 0.5)],
            expectedCount: nil,
        ))

        #expect(activity.phase == .transferring)
        #expect(activity.progress == 0.5)
    }

    @Test func `paused episodes next to downloaded ones pause the series`() throws {
        let activity = try #require(DownloadActivity(
            episodes: [episode("e1", .completed), episode("e2", .paused)],
            expectedCount: nil,
        ))

        #expect(activity.phase == .paused)
        #expect(activity.progress == 0.5)
    }

    @Test func `episodes add up completed ones and the running transfer`() throws {
        let activity = try #require(DownloadActivity(
            episodes: [
                episode("e1", .completed),
                episode("e2", .completed),
                episode("e3", .downloading, progress: 0.5),
                episode("e4", .queued),
            ],
            expectedCount: 10,
        ))

        #expect(activity.phase == .transferring)
        #expect(activity.progress == 0.625)
        #expect(activity.completedCount == 2)
        #expect(activity.totalCount == 4)
    }

    @Test func `an episode prepared on the server does not count towards the progress`() throws {
        let activity = try #require(DownloadActivity(
            episodes: [episode("e1", .completed), episode("e2", .preparing, progress: 0.8)],
            expectedCount: nil,
        ))

        #expect(activity.phase == .preparing)
        #expect(activity.progress == 0.5)
        #expect(activity.ring?.style == .serverPreparation)
    }

    @Test func `episodes stay below full until the last one completes`() throws {
        let activity = try #require(DownloadActivity(
            episodes: [episode("e1", .completed), episode("e2", .downloading, progress: 0.999)],
            expectedCount: nil,
        ))

        #expect(activity.progress == 0.99)
    }

    @Test func `the ring stays between two episodes`() throws {
        let activity = try #require(DownloadActivity(
            episodes: [episode("e1", .completed), episode("e2", .queued)],
            expectedCount: nil,
        ))

        #expect(activity.phase == .queued)
        #expect(activity.ring == .init(progress: 0.5, style: .transfer))
    }

    @Test func `a retried episode replaces its failed attempt`() throws {
        let activity = try #require(DownloadActivity(
            episodes: [
                episode("e1", .failed, id: "first", createdAt: 0),
                episode("e1", .completed, id: "retry", createdAt: 10),
            ],
            expectedCount: 1,
        ))

        #expect(activity.phase == .completed)
        #expect(activity.totalCount == 1)
    }

    @Test func `episodes missing from the series make the download partial`() throws {
        let activity = try #require(DownloadActivity(
            episodes: [episode("e1", .completed), episode("e2", .completed)],
            expectedCount: 10,
        ))

        #expect(activity.phase == .partial)
        #expect(activity.ring == nil)
    }

    @Test func `every queued episode downloaded completes the series`() throws {
        let activity = try #require(DownloadActivity(
            episodes: [episode("e1", .completed), episode("e2", .completed)],
            expectedCount: nil,
        ))

        #expect(activity.phase == .completed)
    }

    @Test func `a failed episode next to downloaded ones is partial`() throws {
        let activity = try #require(DownloadActivity(
            episodes: [episode("e1", .completed), episode("e2", .failed)],
            expectedCount: nil,
        ))

        #expect(activity.phase == .partial)
    }

    @Test func `only failed episodes fail the series`() throws {
        let activity = try #require(DownloadActivity(episodes: [episode("e1", .failed)], expectedCount: nil))

        #expect(activity.phase == .failed)
    }

    @Test func `no episode download means no activity`() {
        #expect(DownloadActivity(episodes: [], expectedCount: 10) == nil)
    }
}
