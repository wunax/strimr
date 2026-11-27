import Foundation
@testable import Strimr
import Testing

struct JellyfinPlaybackTrackTests {
    @Test func `external subtitles numbered first do not shift container indices`() throws {
        let source = try Fixtures.decode(JellyfinMediaSource.self, from: "jellyfin-media-source-external-subtitle")
        let tracks = JellyfinMediaServiceAdapter.playbackTracks(from: source.mediaStreams ?? [])

        let audio = tracks.filter { $0.kind == .audio }
        #expect(audio.map(\.name) == ["VO", "VF"])
        #expect(audio.map(\.sourceIndex) == [1, 2])
        #expect(audio.map(\.id) == ["2", "3"])

        let embeddedSubtitles = tracks.filter { $0.kind == .subtitle && !$0.isExternal }
        #expect(embeddedSubtitles.map(\.sourceIndex) == [3, 4])
        #expect(embeddedSubtitles.map(\.id) == ["4", "5"])
    }

    @Test func `external subtitles numbered last keep container indices`() throws {
        let source = try Fixtures.decode(JellyfinMediaSource.self, from: "jellyfin-media-source-external-subtitle-last")
        let streams = source.mediaStreams ?? []

        #expect(streams.map { JellyfinMediaServiceAdapter.containerStreamIndex(ofStream: $0.index, in: streams) }
            == streams.map(\.index))
    }
}
