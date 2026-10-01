import Foundation
@testable import Strimr
import Testing

struct MediaVersionResolverTests {
    // MARK: - Signature

    @Test func `signature combines height tier, codec, container and dynamic range`() {
        let version = MediaFileVersion.make(
            id: "1",
            height: 2160,
            codec: "hevc",
            container: "mkv",
            dynamicRange: "Dolby Vision",
        )

        #expect(version.signature == "2160:hevc:mkv:dv")
    }

    @Test func `signature marks known video without dynamic range as sdr`() {
        #expect(MediaFileVersion.make(id: "1", height: 1080, codec: "h264", container: "mp4")
            .signature == "1080:h264:mp4:sdr")
    }

    @Test func `signature leaves unknown components empty`() {
        let version = MediaFileVersion.make(
            id: "1",
            width: nil,
            height: nil,
            codec: nil,
            container: nil,
            hasVideoStream: false,
        )

        #expect(version.signature == ":::")
    }

    @Test func `signature normalizes height into tiers`() {
        #expect(MediaFileVersion.make(id: "1", height: 1076).signatureComponents.height == "1080")
        #expect(MediaFileVersion.make(id: "1", height: 2076).signatureComponents.height == "2160")
        #expect(MediaFileVersion.make(id: "1", height: 576).signatureComponents.height == "480")
        #expect(MediaFileVersion.make(id: "1", height: 714).signatureComponents.height == "720")
    }

    @Test func `signature uses width for letterboxed encodes`() {
        #expect(MediaFileVersion.make(id: "1", width: 1920, height: 800).signatureComponents.height == "1080")
        #expect(MediaFileVersion.make(id: "1", width: 3840, height: 1600).signatureComponents.height == "2160")
    }

    @Test func `signature falls back to video resolution`() {
        let fourK = MediaFileVersion.make(
            id: "1",
            width: nil,
            height: nil,
            videoResolution: "4k",
            hasVideoStream: false,
        )
        let standard = MediaFileVersion.make(
            id: "2",
            width: nil,
            height: nil,
            videoResolution: "sd",
            hasVideoStream: false,
        )

        #expect(fourK.signatureComponents.height == "2160")
        #expect(standard.signatureComponents.height == "480")
    }

    @Test func `signature normalizes codec aliases, container lists and case`() {
        let version = MediaFileVersion.make(
            id: "1",
            height: 1080,
            codec: "H265",
            container: "MOV,mp4,m4a",
            dynamicRange: "HDR10",
        )

        #expect(version.signature == "1080:hevc:mov:hdr10")
    }

    @Test func `signature folds every Dolby Vision profile together`() {
        let profile8 = MediaFileVersion.make(id: "1", height: 2160, dynamicRange: "Dolby Vision (HDR10)")
        let profile5 = MediaFileVersion.make(id: "2", height: 2160, dynamicRange: "Dolby Vision")

        #expect(profile8.signatureComponents.dynamicRange == "dv")
        #expect(profile5.signatureComponents.dynamicRange == "dv")
    }

    // MARK: - Matching tiers

    @Test func `exact signature wins over looser matches`() {
        let versions = [
            MediaFileVersion.make(id: "a", height: 2160, codec: "hevc", container: "mp4", dynamicRange: "Dolby Vision"),
            MediaFileVersion.make(id: "b", height: 2160, codec: "hevc", container: "mkv", dynamicRange: "Dolby Vision"),
        ]

        #expect(MediaVersionResolver.bestMatch(for: "2160:hevc:mkv:dv", in: versions)?.id == "b")
    }

    @Test func `height codec and dynamic range match ignores container`() {
        let versions = [
            MediaFileVersion.make(id: "a", height: 2160, codec: "hevc", container: "mkv", dynamicRange: "HDR10"),
            MediaFileVersion.make(id: "b", height: 2160, codec: "hevc", container: "mp4", dynamicRange: "Dolby Vision"),
        ]

        #expect(MediaVersionResolver.bestMatch(for: "2160:hevc:mkv:dv", in: versions)?.id == "b")
    }

    @Test func `height and codec match ignores dynamic range`() {
        let versions = [
            MediaFileVersion.make(id: "a", height: 2160, codec: "av1", container: "mkv", dynamicRange: "Dolby Vision"),
            MediaFileVersion.make(id: "b", height: 2160, codec: "hevc", container: "mp4", dynamicRange: "HDR10"),
        ]

        #expect(MediaVersionResolver.bestMatch(for: "2160:hevc:mkv:dv", in: versions)?.id == "b")
    }

    @Test func `height alone is the last tier`() {
        let versions = [
            MediaFileVersion.make(id: "a", height: 1080, codec: "hevc", container: "mkv"),
            MediaFileVersion.make(id: "b", height: 2160, codec: "av1", container: "mp4"),
        ]

        #expect(MediaVersionResolver.bestMatch(for: "2160:hevc:mkv:dv", in: versions)?.id == "b")
    }

    @Test func `no match when height differs`() {
        let versions = [MediaFileVersion.make(id: "a", height: 1080, codec: "hevc", container: "mkv")]

        #expect(MediaVersionResolver.bestMatch(for: "2160:hevc:mkv:sdr", in: versions) == nil)
    }

    @Test func `unknown preferred height only matches exactly`() {
        let versions = [MediaFileVersion.make(id: "a", width: nil, height: nil, codec: "hevc", container: "mkv")]

        #expect(MediaVersionResolver.bestMatch(for: ":h264:mkv:sdr", in: versions) == nil)
        #expect(MediaVersionResolver.bestMatch(for: ":hevc:mkv:sdr", in: versions)?.id == "a")
    }

    @Test func `original version beats optimized version at the same tier`() {
        let versions = [
            MediaFileVersion.make(id: "optimized", height: 1080, codec: "h264", container: "mp4", isOptimized: true),
            MediaFileVersion.make(id: "original", height: 1080, codec: "h264", container: "mp4"),
        ]

        #expect(MediaVersionResolver.bestMatch(for: "1080:h264:mp4:sdr", in: versions)?.id == "original")
    }

    @Test func `server order breaks ties`() {
        let versions = [
            MediaFileVersion.make(id: "first", height: 1080, codec: "h264", container: "mp4"),
            MediaFileVersion.make(id: "second", height: 1080, codec: "h264", container: "mp4"),
        ]

        #expect(MediaVersionResolver.bestMatch(for: "1080:h264:mp4:sdr", in: versions)?.id == "first")
    }

    @Test func `unavailable versions are ignored`() {
        let versions = [
            MediaFileVersion.make(
                id: "deleted",
                height: 2160,
                codec: "hevc",
                container: "mkv",
                dynamicRange: "HDR10",
                isAvailable: false,
            ),
            MediaFileVersion.make(id: "fallback", height: 2160, codec: "av1", container: "mkv"),
        ]

        #expect(MediaVersionResolver.bestMatch(for: "2160:hevc:mkv:hdr10", in: versions)?.id == "fallback")
    }

    // MARK: - Resolution order

    @Test func `explicit choice wins over preference`() {
        let versions = [MediaFileVersion.make(id: "a", height: 1080), MediaFileVersion.make(id: "b", height: 2160)]
        let resolved = MediaVersionResolver.resolve(.explicit(versionID: "b"), in: versions, default: \.first)

        #expect(resolved?.id == "b")
    }

    @Test func `unavailable explicit choice falls back to default`() {
        let versions = [
            MediaFileVersion.make(id: "a", height: 1080),
            MediaFileVersion.make(id: "b", height: 2160, isAvailable: false),
        ]
        let resolved = MediaVersionResolver.resolve(.explicit(versionID: "b"), in: versions, default: \.first)

        #expect(resolved?.id == "a")
    }

    @Test func `preference id is compared case-insensitively`() {
        let versions = [MediaFileVersion.make(id: "abc", height: 1080), MediaFileVersion.make(id: "DEF", height: 1080)]
        let resolved = MediaVersionResolver.resolve(
            .preferred(preference(versionID: "def", signature: "2160:hevc:mkv:dv")),
            in: versions,
            default: \.first,
        )

        #expect(resolved?.id == "DEF")
    }

    @Test func `preference falls back to signature on another item`() {
        let versions = [
            MediaFileVersion.make(id: "ep2-1080", height: 1080, codec: "h264", container: "mkv"),
            MediaFileVersion.make(
                id: "ep2-2160",
                height: 2160,
                codec: "hevc",
                container: "mkv",
                dynamicRange: "Dolby Vision",
            ),
        ]
        let resolved = MediaVersionResolver.resolve(
            .preferred(preference(versionID: "ep1-2160", signature: "2160:hevc:mkv:dv")),
            in: versions,
            default: \.first,
        )

        #expect(resolved?.id == "ep2-2160")
    }

    @Test func `preference without equivalent uses default`() {
        let versions = [MediaFileVersion.make(id: "a", height: 720), MediaFileVersion.make(id: "b", height: 1080)]
        let resolved = MediaVersionResolver.resolve(
            .preferred(preference(versionID: nil, signature: "2160:hevc:mkv:dv")),
            in: versions,
            default: { $0.last },
        )

        #expect(resolved?.id == "b")
    }

    @Test func `unavailable default falls back to first available version`() {
        let versions = [
            MediaFileVersion.make(id: "a", height: 1080, isAvailable: false),
            MediaFileVersion.make(id: "b", height: 720),
        ]

        #expect(MediaVersionResolver.resolve(.automatic, in: versions, default: \.first)?.id == "b")
    }

    @Test func `nothing is resolved when no version is available`() {
        let versions = [MediaFileVersion.make(id: "a", height: 1080, isAvailable: false)]

        #expect(MediaVersionResolver.resolve(.automatic, in: versions, default: \.first) == nil)
    }

    // MARK: - Helpers

    private func preference(versionID: String?, signature: String) -> MediaVersionPreference {
        MediaVersionPreference(versionID: versionID, signature: signature, updatedAt: Date(timeIntervalSince1970: 0))
    }
}
