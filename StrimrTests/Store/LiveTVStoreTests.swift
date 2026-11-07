import Foundation
@testable import Strimr
import Testing

@MainActor
struct LiveTVStoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func program(id: String, recordingID: String?, seriesRecordingID: String? = nil) -> LiveTVProgram {
        LiveTVProgram(
            id: id,
            channelID: "1",
            channelIdentity: LiveTVChannelIdentity(providerID: "1", lineupID: nil, dvrID: nil),
            title: "Program \(id)",
            seriesTitle: nil,
            summary: nil,
            startDate: now,
            endDate: now.addingTimeInterval(3600),
            thumbPath: nil,
            artPath: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            isLive: false,
            isPremiere: false,
            recordingID: recordingID,
            seriesRecordingID: seriesRecordingID,
            recordingStatus: nil,
            providerGUID: nil,
        )
    }

    private func loadedStore(service: StubLiveTVService) async -> LiveTVStore {
        let store = LiveTVStore(service: service)
        await store.load()
        return store
    }

    @Test func `the guide covers the loaded range only`() async {
        let store = await loadedStore(service: StubLiveTVService())

        #expect(store.guideCovers(Date()))
        #expect(store.guideCovers(store.guideStart))
        #expect(!store.guideCovers(store.guideEnd))
        #expect(!store.guideCovers(Date().addingTimeInterval(12 * 3600)))
    }

    @Test func `cancelling a recording clears it from the cached programs`() async throws {
        let service = StubLiveTVService()
        service.loadedPrograms = [program(id: "a", recordingID: "recording")]
        let store = await loadedStore(service: service)
        #expect(store.programs.first?.isScheduledForRecording == true)

        service.loadedPrograms = [program(id: "a", recordingID: nil)]
        try await store.cancelRecording(id: "recording")

        #expect(service.cancelledRecordingIDs == ["recording"])
        #expect(store.programs.first?.isScheduledForRecording == false)
    }

    @Test func `deleting a rule clears it from the cached programs`() async throws {
        let service = StubLiveTVService()
        service.loadedPrograms = [program(id: "a", recordingID: nil, seriesRecordingID: "rule")]
        let store = await loadedStore(service: service)
        #expect(store.programs.first?.isScheduledForRecording == true)

        service.loadedPrograms = [program(id: "a", recordingID: nil)]
        try await store.deleteRule(id: "rule")

        #expect(service.deletedRuleIDs == ["rule"])
        #expect(store.programs.first?.isScheduledForRecording == false)
    }

    @Test func `favorites keep their own order whatever the channel sort`() async throws {
        let service = StubLiveTVService()
        service.loadedChannels = [
            channel("a", number: "3", favorite: true),
            channel("b", number: "1", favorite: true),
            channel("c", number: "2"),
        ]
        let store = await loadedStore(service: service)

        #expect(store.channels.map(\.providerID) == ["b", "c", "a"])
        #expect(store.favoriteChannels.map(\.providerID) == ["a", "b"])

        try await store.reorderFavorites([store.channels[0], store.channels[2]])
        store.channelSort = .name

        #expect(store.channels.map(\.providerID) == ["a", "b", "c"])
        #expect(store.favoriteChannels.map(\.providerID) == ["b", "a"])

        await store.toggleFavorite(store.channels[2])

        #expect(store.favoriteChannels.map(\.providerID) == ["b", "a", "c"])
    }

    @Test func `a removal reloads the whole range the guide has extended to`() async throws {
        let service = StubLiveTVService()
        service.loadedPrograms = [program(id: "a", recordingID: "recording")]
        let store = await loadedStore(service: service)
        await store.extendGuide(forward: true)
        let range = (store.guideStart, store.guideEnd)

        try await store.cancelRecording(id: "recording")

        #expect((store.guideStart, store.guideEnd) == range)
        #expect(service.programRequests.last?.0 == range.0)
        #expect(service.programRequests.last?.1 == range.1)
    }
}

@MainActor
private final class StubLiveTVService: MediaLiveTVService, MediaDVRService {
    var loadedPrograms: [LiveTVProgram] = []
    private(set) var programRequests: [(Date, Date)] = []
    private(set) var cancelledRecordingIDs: [String] = []
    private(set) var deletedRuleIDs: [String] = []

    var dvr: (any MediaDVRService)? {
        self
    }

    var supportsServerCaptureBuffer: Bool {
        false
    }

    var supportsCompletedRecordings: Bool {
        false
    }

    var canManageRecordings: Bool {
        true
    }

    var canDeleteRecordings: Bool {
        true
    }

    func isAvailable() async throws -> Bool {
        true
    }

    var loadedChannels = [channel("1", number: "1")]

    func channels() async throws -> [LiveTVChannel] {
        loadedChannels
    }

    func programs(from start: Date, to end: Date) async throws -> [LiveTVProgram] {
        programRequests.append((start, end))
        return loadedPrograms
    }

    func onNow() async throws -> [LiveTVOnNowSection] {
        []
    }

    func setFavorite(_: Bool, channel _: LiveTVChannel) async throws {}

    func reorderFavorites(_: [LiveTVChannel]) async throws {}

    func startPlayback(
        channel _: LiveTVChannel,
        route _: LiveTVRoutePreference,
    ) async throws -> any LiveTVPlaybackSession {
        throw URLError(.unsupportedURL)
    }

    func upcomingRecordings() async throws -> [DVRRecording] {
        []
    }

    func recordingRules() async throws -> [DVRRecordingRule] {
        []
    }

    func completedRecordings() async throws -> [DVRRecording] {
        []
    }

    func recordingTemplate(for _: LiveTVProgram) async throws -> DVRRecordingTemplate {
        throw URLError(.unsupportedURL)
    }

    func schedule(_: DVRRecordingRequest) async throws {}

    func update(rule _: DVRRecordingRule, options _: [String: String]) async throws {}

    func cancel(recordingID: String) async throws {
        cancelledRecordingIDs.append(recordingID)
    }

    func delete(ruleID: String) async throws {
        deletedRuleIDs.append(ruleID)
    }

    func deleteCompleted(recordingID _: String) async throws {}

    func reloadGuide() async throws {}
}

private func channel(_ id: String, number: String?, favorite: Bool = false) -> LiveTVChannel {
    LiveTVChannel(
        providerID: id,
        title: "Channel \(id)",
        callSign: nil,
        number: number,
        thumbPath: nil,
        artPath: nil,
        lineupID: nil,
        dvrID: nil,
        isHD: true,
        isFavorite: favorite,
    )
}
