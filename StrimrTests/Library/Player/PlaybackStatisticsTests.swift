import AetherEngine
import CoreGraphics
import Foundation
@testable import Strimr
import Testing

struct PlaybackStatisticsTests {
    private let locale = Locale(identifier: "en_US")

    @Test func `describes HDR source mapped to SDR display`() {
        var source = hevcSource()
        source.presentedVideoFormat = .sdr

        let statistics = PlaybackStatistics(source, locale: locale)

        #expect(statistics.value(for: .codec) == "HEVC · Main 10")
        #expect(statistics.value(for: .resolution) == "3840×2160 → 1920×1080")
        #expect(statistics.value(for: .frameRate) == String(localized: "player.statistics.unit.fps \("23.976")"))
        #expect(statistics.value(for: .dynamicRange) == "HDR10 → SDR")
        #expect(statistics.value(for: .color) == "BT.2020 · PQ (SMPTE ST 2084) · BT.2020 NCL · Limited")
        #expect(statistics
            .value(for: .pixelFormat) == "yuv420p10le · \(String(localized: "player.statistics.bitDepth \(10)"))")
    }

    @Test func `keeps matching formats as one value`() {
        var source = hevcSource()
        source.sourceVideoFormat = .dolbyVision
        source.presentedVideoFormat = .dolbyVision
        source.dolbyVisionProfile = 8

        let statistics = PlaybackStatistics(source, locale: locale)

        #expect(statistics.value(for: .dynamicRange) == "Dolby Vision P8")
    }

    @Test func `shows dolby vision profile conversion`() {
        var source = hevcSource()
        source.sourceVideoFormat = .dolbyVision
        source.presentedVideoFormat = .dolbyVision
        source.dolbyVisionProfile = 7
        source.dolbyVisionConversion = .profile7ToProfile81

        let statistics = PlaybackStatistics(source, locale: locale)

        #expect(statistics.value(for: .dynamicRange) == "Dolby Vision P7 → Dolby Vision P8.1")
    }

    @Test func `names AV foundation as decoder on native routes only`() {
        var source = hevcSource()
        source.videoRoute = .loopback
        #expect(PlaybackStatistics(source, locale: locale).value(for: .decoder) == "AVFoundation")

        source.videoRoute = .software
        #expect(PlaybackStatistics(source, locale: locale).value(for: .decoder) == nil)

        source.videoDecoder = "VideoToolbox HEVC (HW)"
        #expect(PlaybackStatistics(source, locale: locale).value(for: .decoder) == "VideoToolbox HEVC (HW)")
    }

    @Test func `shows decoded pixel buffer on software path`() {
        var source = hevcSource()
        source.decodedVideoFormat = DecodedVideoFormat(
            frame: hdrFormat(pixelFormat: "p010le"),
            pixelBufferFormat: "x420",
        )

        let statistics = PlaybackStatistics(source, locale: locale)

        let depth = String(localized: "player.statistics.bitDepth \(10)")
        #expect(statistics.value(for: .pixelFormat) == "p010le · \(depth) → P010 (x420)")
    }

    @Test func `hides video section for audio only playback`() {
        var source = hevcSource()
        source.videoRoute = .audio

        let statistics = PlaybackStatistics(source, locale: locale)

        #expect(!statistics.sections.contains { $0.kind == .video })
    }

    @Test func `labels transcode with its quality`() {
        var source = hevcSource()
        source.context = PlaybackStatisticsContext(method: .transcode, quality: .p720_4mbps)

        let statistics = PlaybackStatistics(source, locale: locale)

        let expected = "\(String(localized: "player.statistics.method.transcode")) · \(TranscodeQualityPreset.p720_4mbps.title)"
        #expect(statistics.value(for: .method) == expected)
    }

    @Test func `describes object audio track`() {
        var source = hevcSource()
        source.audioTrack = TrackInfo(
            id: 1,
            name: "English",
            codec: "truehd",
            language: "eng",
            channels: 8,
            isDefault: true,
            sampleRate: 48000,
            bitsPerSample: 24,
            channelLayout: "7.1",
            profile: "Dolby TrueHD + Dolby Atmos",
        )

        let statistics = PlaybackStatistics(source, locale: locale)

        let depth = String(localized: "player.statistics.bitDepth \(24)")
        #expect(statistics.value(for: .codec) == "HEVC · Main 10")
        let audio = statistics.sections.first { $0.kind == .audio }
        #expect(audio?.rows.first?.value == "TrueHD (Dolby TrueHD + Dolby Atmos)")
        #expect(audio?.rows.contains { $0.field == .channels && $0.value == "7.1" } == true)
        #expect(audio?.rows.contains {
            $0.field == .sampleRate && $0.value == "\(String(localized: "player.statistics.unit.kilohertz \("48")")) · \(depth)"
        } == true)
    }

    @Test func `prefers player buffer over engine buffered position`() {
        var source = hevcSource()
        source.bufferedAhead = 4
        #expect(PlaybackStatistics(source, locale: locale).value(for: .buffer)
            == String(localized: "player.statistics.unit.seconds \("4.0")"))

        source.telemetry = telemetry(forwardBufferSeconds: 12.34)
        #expect(PlaybackStatistics(source, locale: locale).value(for: .buffer)
            == String(localized: "player.statistics.unit.seconds \("12.3")"))
    }

    @Test func `hides software buffer that only covers decoded frames`() {
        var source = hevcSource()
        source.bufferedAhead = 0.2
        source.telemetry = telemetry(forwardBufferSeconds: nil, displayCushionSeconds: 0.2)
        #expect(PlaybackStatistics(source, locale: locale).value(for: .buffer) == nil)

        source.bufferedAhead = 38
        #expect(PlaybackStatistics(source, locale: locale).value(for: .buffer)
            == String(localized: "player.statistics.unit.seconds \("38.0")"))
    }

    @Test func `balances sections across columns`() {
        let rows = { (count: Int) in (0 ..< count).map { _ in PlaybackStatistics.Row(field: .codec, value: "") } }
        let statistics = PlaybackStatistics(sections: [
            .init(kind: .playback, rows: rows(3)),
            .init(kind: .video, rows: rows(8)),
            .init(kind: .audio, rows: rows(6)),
            .init(kind: .subtitles, rows: rows(2)),
            .init(kind: .network, rows: rows(5)),
        ])

        #expect(statistics.columns(1).map { $0.map(\.kind) } == [[.playback, .video, .audio, .subtitles, .network]])
        #expect(statistics.columns(2).map { $0.map(\.kind) } == [[.playback, .video], [.audio, .subtitles, .network]])
        #expect(statistics.columns(3).map { $0.map(\.kind) } == [[.playback, .video], [.audio], [.subtitles, .network]])
    }

    @Test func `formats live telemetry`() {
        var source = hevcSource()
        source.telemetry = telemetry(forwardBufferSeconds: nil)

        let statistics = PlaybackStatistics(source, locale: locale)

        let current = String(localized: "player.statistics.unit.megabits \("24.5")")
        let average = String(localized: "player.statistics.unit.megabits \("8.25")")
        #expect(statistics.value(for: .mediaBitrate)
            == String(localized: "player.statistics.bitrate.currentAverage \(current) \(average)"))
        #expect(statistics.value(for: .droppedFrames) == "3")
        #expect(statistics.value(for: .avSync) == String(localized: "player.statistics.unit.milliseconds \("+12")"))
        #expect(statistics.value(for: .frameRate)
            ==
            "\(String(localized: "player.statistics.unit.fps \("23.976")")) · \(String(localized: "player.statistics.frameRate.observed \("23.9")"))")
    }

    @Test func `omits subtitle format when burned in`() {
        var source = hevcSource()
        source.subtitleCodec = "hdmv_pgs_subtitle"
        source.subtitleRenderer = .overlay
        #expect(PlaybackStatistics(source, locale: locale).value(for: .subtitleFormat) == "PGS")

        source.subtitleRenderer = .burnedIn
        let statistics = PlaybackStatistics(source, locale: locale)
        #expect(statistics.value(for: .subtitleFormat) == nil)
        #expect(statistics.value(for: .subtitleRendering)
            == String(localized: "player.statistics.subtitles.burnedIn"))
    }

    @Test func `drops empty sections`() {
        let statistics = PlaybackStatistics(PlaybackStatisticsSource(), locale: locale)

        #expect(statistics.sections.isEmpty)
    }

    private func hevcSource() -> PlaybackStatisticsSource {
        PlaybackStatisticsSource(
            context: PlaybackStatisticsContext(method: .directPlay),
            videoRoute: .software,
            containerFormat: "matroska,webm",
            videoCodec: "hevc",
            videoStreamFormat: hdrFormat(pixelFormat: "yuv420p10le"),
            sourceVideoSize: CGSize(width: 3840, height: 2160),
            displayVideoSize: CGSize(width: 1920, height: 1080),
            frameRate: 24000.0 / 1001.0,
            videoBitrate: 0,
            sourceVideoFormat: .hdr10,
            presentedVideoFormat: .hdr10,
        )
    }

    private func hdrFormat(pixelFormat: String) -> VideoStreamFormat {
        VideoStreamFormat(
            pixelFormat: pixelFormat,
            bitDepth: 10,
            colorPrimaries: "bt2020",
            transfer: "smpte2084",
            matrix: "bt2020nc",
            range: "tv",
            profile: "Main 10",
        )
    }

    private func telemetry(forwardBufferSeconds: Double?, displayCushionSeconds: Double? = nil) -> LiveTelemetry {
        LiveTelemetry(
            instantBitrateMbps: 24.5,
            averageBitrateMbps: 8.25,
            audioBridgeBitrateMbps: nil,
            observedFps: 23.9,
            droppedFrameCount: 3,
            forwardBufferSeconds: forwardBufferSeconds,
            displayCushionSeconds: displayCushionSeconds,
            cachedBytes: nil,
            networkThroughputMbps: nil,
            networkTransferredBytes: nil,
            avSyncGapMs: 12.2,
            producerRestartCount: 0,
            muxedBytesLifetime: 0,
            serverBytesSentLifetime: 0,
            serverRequestCount: 0,
            demuxerBytesFetched: 0,
            audioBridgeLiveBytes: 0,
            rssMb: 0,
        )
    }
}
