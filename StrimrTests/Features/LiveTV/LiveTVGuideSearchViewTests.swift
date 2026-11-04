import Foundation
@testable import Strimr
import Testing

@MainActor
struct LiveTVGuideSearchViewTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func program(_ title: String, startsInHours hours: TimeInterval, series: String? = nil) -> LiveTVProgram {
        LiveTVProgram(
            id: title,
            channelID: "1",
            channelIdentity: LiveTVChannelIdentity(providerID: "1", lineupID: nil, dvrID: nil),
            title: title,
            seriesTitle: series,
            summary: nil,
            startDate: now.addingTimeInterval(hours * 3600),
            endDate: now.addingTimeInterval((hours + 1) * 3600),
            thumbPath: nil,
            artPath: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            isLive: false,
            isPremiere: false,
            recordingID: nil,
            seriesRecordingID: nil,
            recordingStatus: nil,
            providerGUID: nil,
        )
    }

    private func titles(_ programs: [LiveTVProgram], query: String) -> [String] {
        LiveTVGuideSearchView.matchingPrograms(programs, query: query, now: now).map(\.title)
    }

    @Test func `finds programs across the next 24 hours, soonest first`() {
        let programs = [program("Film du soir", startsInHours: 23), program("Film du matin", startsInHours: 10)]

        #expect(titles(programs, query: "film") == ["Film du matin", "Film du soir"])
    }

    @Test func `leaves out what has ended and what airs after 24 hours`() {
        let programs = [
            program("Film fini", startsInHours: -2),
            program("Film en cours", startsInHours: -0.5),
            program("Film demain", startsInHours: 25),
        ]

        #expect(titles(programs, query: "film") == ["Film en cours"])
    }

    @Test func `matches the series title`() {
        let programs = [program("Épisode 3", startsInHours: 1, series: "Kaamelott")]

        #expect(titles(programs, query: "kaamelott") == ["Épisode 3"])
    }

    @Test func `an empty query finds nothing`() {
        #expect(titles([program("Film", startsInHours: 1)], query: "").isEmpty)
    }
}
