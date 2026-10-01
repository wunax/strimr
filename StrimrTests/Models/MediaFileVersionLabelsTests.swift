import Foundation
@testable import Strimr
import Testing

struct MediaFileVersionLabelsTests {
    @Test func `technical label combines resolution, dynamic range and codec`() {
        let version = MediaFileVersion.make(id: "1", height: 2160, codec: "hevc", dynamicRange: "Dolby Vision")

        #expect(version.technicalLabel == "4K · Dolby Vision · HEVC")
        #expect(version.shortLabel == "4K DV")
    }

    @Test func `short label omits standard dynamic range`() {
        #expect(MediaFileVersion.make(id: "1", height: 1080).shortLabel == "1080p")
    }

    @Test func `titles are only used when they differ between versions`() {
        let distinct = [
            MediaFileVersion.make(id: "1", title: "Director's Cut", height: 1080),
            MediaFileVersion.make(id: "2", title: "Theatrical", height: 2160, codec: "hevc"),
        ]
        let identical = [
            MediaFileVersion.make(id: "1", title: "Movie", height: 1080),
            MediaFileVersion.make(id: "2", title: "Movie", height: 2160, codec: "hevc"),
        ]

        #expect(MediaFileVersion.displayLabels(for: distinct) == ["Director's Cut", "Theatrical"])
        #expect(MediaFileVersion.displayLabels(for: identical) == ["1080p · H.264", "4K · HEVC"])
    }

    @Test func `colliding labels gain the size, then the file name`() {
        let bySize = [
            MediaFileVersion.make(id: "1", height: 1080, sizeBytes: 1_000_000_000),
            MediaFileVersion.make(id: "2", height: 1080, sizeBytes: 4_000_000_000),
        ]
        let byName = [
            MediaFileVersion.make(id: "1", height: 1080, path: "/movies/Movie VF.mkv"),
            MediaFileVersion.make(id: "2", height: 1080, path: "/movies/Movie VO.mkv"),
        ]

        let sizeLabels = MediaFileVersion.displayLabels(for: bySize)
        #expect(sizeLabels[0] != sizeLabels[1])
        #expect(sizeLabels[0].hasPrefix("1080p · H.264 · "))
        #expect(MediaFileVersion.displayLabels(for: byName) == [
            "1080p · H.264 · Movie VF.mkv",
            "1080p · H.264 · Movie VO.mkv",
        ])
    }

    @Test func `optimized versions are prefixed with their profile`() {
        let version = MediaFileVersion.make(id: "1", height: 720, isOptimized: true, optimizationTarget: "Mobile")
        let prefix = String(localized: "media.versions.optimized")

        #expect(version.displayLabel(among: [version]) == "\(prefix) (Mobile) · 720p · H.264")
    }

    @Test func `detail label lists audio, size and file name`() {
        let version = MediaFileVersion.make(
            id: "1",
            height: 2160,
            audioCodec: "truehd",
            audioChannels: 8,
            path: "/movies/Movie (2160p).mkv",
        )

        #expect(version.detailLabel == "TrueHD 7.1 · Movie (2160p).mkv")
    }
}
