import Foundation
@testable import Strimr
import Testing

@MainActor
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

        let externalSubtitles = tracks.filter(\.isExternal)
        #expect(externalSubtitles.map(\.sourceIndex) == [5])
        #expect(externalSubtitles.map(\.id) == ["0"])
    }

    @Test func `maps the server's default audio stream to its container index`() throws {
        let source = try Fixtures.decode(JellyfinMediaSource.self, from: "jellyfin-media-source-external-subtitle")
        let streams = source.mediaStreams ?? []

        #expect(source.defaultAudioStreamIndex == 2)
        #expect(JellyfinMediaServiceAdapter.containerStreamIndex(ofStream: 2, in: streams) == 1)
    }

    @Test func `external and embedded tracks never share an index`() throws {
        let tracks = try Self.tracks(from: "jellyfin-media-source-several-external-subtitles")

        #expect(tracks.filter { !$0.isExternal }.map(\.sourceIndex) == [1, 2, 3])
        #expect(tracks.filter(\.isExternal).map(\.sourceIndex) == [4, 5, 6])

        let playerTracks = PlayerViewModel.sourcePlayerTracks(tracks, selectedAudioIndex: nil, selectedSubtitleIndex: 6)
        #expect(Set(playerTracks.map(\.id)).count == playerTracks.count)
        let selected = playerTracks.filter(\.isSelected)
        #expect(selected.map(\.providerStreamID) == [6])
        #expect(selected.map(\.isExternal) == [false])
    }

    @Test func `maps only the file's own tracks to engine indices`() throws {
        let tracks = try Self.tracks(from: "jellyfin-media-source-several-external-subtitles")

        #expect(PlayerViewModel.providerStreamIDsByFFIndex(tracks) == [1: 4, 2: 5, 3: 6])
    }

    @Test func `reports the server's audio stream index for a container audio index`() throws {
        let tracks = try Self.tracks(from: "jellyfin-media-source-several-external-subtitles")
        let selection = PlaybackStreamSelection(audioStreamIndex: 2, subtitleStreamIndex: 1, subtitleIsOff: false)

        let reported = JellyfinMediaServiceAdapter.serverSelection(selection, tracks: tracks)

        #expect(reported == PlaybackStreamSelection(audioStreamIndex: 5, subtitleStreamIndex: 1, subtitleIsOff: false))
    }

    @Test func `external subtitles numbered last keep container indices`() throws {
        let source = try Fixtures.decode(JellyfinMediaSource.self, from: "jellyfin-media-source-external-subtitle-last")
        let streams = source.mediaStreams ?? []

        #expect(streams.map { JellyfinMediaServiceAdapter.containerStreamIndex(ofStream: $0.index, in: streams) }
            == streams.map(\.index))
    }

    private static func tracks(from fixture: String) throws -> [PlaybackTrack] {
        let source = try Fixtures.decode(JellyfinMediaSource.self, from: fixture)
        return JellyfinMediaServiceAdapter.playbackTracks(from: source.mediaStreams ?? [])
    }
}
