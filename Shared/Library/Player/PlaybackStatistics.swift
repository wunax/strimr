import AetherEngine
import CoreGraphics
import Foundation

struct PlaybackStatisticsContext: Equatable {
    var method: PlaybackMethod?
    var quality: TranscodeQualityPreset = .original
    var burnsSubtitles = false
}

enum PlaybackStatisticsSubtitleRenderer: Equatable {
    case burnedIn
    case native
    case styled
    case overlay
}

/// Everything the panel reads, gathered from the engine and the playback plan at one instant.
struct PlaybackStatisticsSource {
    var context = PlaybackStatisticsContext()
    var videoRoute: VideoRoute = .none
    var containerFormat: String?
    var videoCodec: String?
    var videoStreamFormat: VideoStreamFormat?
    var decodedVideoFormat: DecodedVideoFormat?
    var sourceVideoSize: CGSize?
    var displayVideoSize: CGSize?
    var frameRate: Double?
    var videoBitrate: Int64 = 0
    var sourceVideoFormat: VideoFormat = .sdr
    var presentedVideoFormat: VideoFormat = .sdr
    var dolbyVisionProfile: Int?
    var dolbyVisionConversion: DolbyVisionConversion?
    var videoDecoder: String?
    var audioTrack: TrackInfo?
    var audioDecoder: String?
    var audioDelivery: AudioDelivery = .none
    var subtitleCodec: String?
    var subtitleRenderer: PlaybackStatisticsSubtitleRenderer?
    var bufferedAhead: Double?
    var telemetry: LiveTelemetry?
}

struct PlaybackStatistics: Equatable {
    enum SectionKind: Hashable {
        case playback
        case video
        case audio
        case subtitles
        case network

        var title: LocalizedStringResource {
            switch self {
            case .playback: "player.statistics.section.playback"
            case .video: "player.statistics.section.video"
            case .audio: "player.statistics.section.audio"
            case .subtitles: "player.statistics.section.subtitles"
            case .network: "player.statistics.section.network"
            }
        }
    }

    enum Field: Hashable {
        case method
        case route
        case container
        case codec
        case resolution
        case frameRate
        case dynamicRange
        case color
        case pixelFormat
        case decoder
        case bitrate
        case channels
        case sampleRate
        case audioOutput
        case objects
        case subtitleFormat
        case subtitleRendering
        case mediaBitrate
        case throughput
        case buffer
        case droppedFrames
        case avSync
        case cache

        var title: LocalizedStringResource {
            switch self {
            case .method: "player.statistics.field.method"
            case .route: "player.statistics.field.route"
            case .container: "player.statistics.field.container"
            case .codec: "player.statistics.field.codec"
            case .resolution: "player.statistics.field.resolution"
            case .frameRate: "player.statistics.field.frameRate"
            case .dynamicRange: "player.statistics.field.dynamicRange"
            case .color: "player.statistics.field.color"
            case .pixelFormat: "player.statistics.field.pixelFormat"
            case .decoder: "player.statistics.field.decoder"
            case .bitrate: "player.statistics.field.bitrate"
            case .channels: "player.statistics.field.channels"
            case .sampleRate: "player.statistics.field.sampleRate"
            case .audioOutput: "player.statistics.field.audioOutput"
            case .objects: "player.statistics.field.objects"
            case .subtitleFormat: "player.statistics.field.subtitleFormat"
            case .subtitleRendering: "player.statistics.field.subtitleRendering"
            case .mediaBitrate: "player.statistics.field.mediaBitrate"
            case .throughput: "player.statistics.field.throughput"
            case .buffer: "player.statistics.field.buffer"
            case .droppedFrames: "player.statistics.field.droppedFrames"
            case .avSync: "player.statistics.field.avSync"
            case .cache: "player.statistics.field.cache"
            }
        }
    }

    struct Row: Equatable, Identifiable {
        let field: Field
        let value: String

        var id: Field {
            field
        }
    }

    struct Section: Equatable, Identifiable {
        let kind: SectionKind
        let rows: [Row]

        var id: SectionKind {
            kind
        }
    }

    let sections: [Section]

    func value(for field: Field) -> String? {
        sections.lazy.flatMap(\.rows).first { $0.field == field }?.value
    }
}

extension PlaybackStatistics {
    init(_ source: PlaybackStatisticsSource, locale: Locale = .current) {
        let formatter = StatisticsFormatter(locale: locale)
        let sections: [Section] = [
            Section(kind: .playback, rows: Self.playbackRows(source)),
            Section(kind: .video, rows: Self.videoRows(source, formatter: formatter)),
            Section(kind: .audio, rows: Self.audioRows(source, formatter: formatter)),
            Section(kind: .subtitles, rows: Self.subtitleRows(source)),
            Section(kind: .network, rows: Self.networkRows(source, formatter: formatter)),
        ]
        self.init(sections: sections.filter { !$0.rows.isEmpty })
    }

    private static func playbackRows(_ source: PlaybackStatisticsSource) -> [Row] {
        var rows: [Row] = []
        if let method = source.context.method {
            var value = switch method {
            case .directPlay: String(localized: "player.statistics.method.directPlay")
            case .transcode: String(localized: "player.statistics.method.transcode")
            case .offline: String(localized: "player.statistics.method.offline")
            }
            if method == .transcode, !source.context.quality.isOriginal {
                value += " · \(source.context.quality.title)"
            }
            rows.append(Row(field: .method, value: value))
        }
        if let route = routeLabel(source.videoRoute) {
            rows.append(Row(field: .route, value: route))
        }
        if let container = source.containerFormat.flatMap(containerLabel) {
            rows.append(Row(field: .container, value: container))
        }
        return rows
    }

    private static func videoRows(_ source: PlaybackStatisticsSource, formatter: StatisticsFormatter) -> [Row] {
        guard source.videoRoute != .audio, source.videoCodec != nil || source.videoStreamFormat != nil else {
            return []
        }
        var rows: [Row] = []
        let format = source.videoStreamFormat

        if let codec = source.videoCodec.map(videoCodecLabel) {
            rows.append(Row(field: .codec, value: joined(codec, format?.profile)))
        }

        if let resolution = resolutionLabel(source: source.sourceVideoSize, display: source.displayVideoSize) {
            rows.append(Row(field: .resolution, value: resolution))
        }

        if let frameRate = frameRateLabel(
            nominal: source.frameRate,
            observed: source.telemetry?.observedFps,
            formatter: formatter,
        ) {
            rows.append(Row(field: .frameRate, value: frameRate))
        }

        rows.append(Row(field: .dynamicRange, value: dynamicRangeLabel(source)))

        let color = [format?.colorPrimariesLabel, format?.transferLabel, format?.matrixLabel, format?.rangeLabel]
            .compactMap(\.self)
        if !color.isEmpty {
            rows.append(Row(field: .color, value: color.joined(separator: " · ")))
        }

        if let pixelFormat = pixelFormatLabel(source: format, decoded: source.decodedVideoFormat) {
            rows.append(Row(field: .pixelFormat, value: pixelFormat))
        }

        if let decoder = source.videoDecoder ?? nativeDecoderLabel(source.videoRoute) {
            rows.append(Row(field: .decoder, value: decoder))
        }

        if source.videoBitrate > 0 {
            rows.append(Row(field: .bitrate, value: formatter.megabits(Double(source.videoBitrate) / 1_000_000)))
        }
        return rows
    }

    private static func audioRows(_ source: PlaybackStatisticsSource, formatter: StatisticsFormatter) -> [Row] {
        guard let track = source.audioTrack else { return [] }
        var rows = [Row(field: .codec, value: audioCodecLabel(track))]

        if let channels = channelsLabel(track) {
            rows.append(Row(field: .channels, value: channels))
        }

        let sampleRate = track.sampleRate > 0 ? formatter.kilohertz(Double(track.sampleRate) / 1000) : nil
        let depth = track.bitsPerSample > 0
            ? String(localized: "player.statistics.bitDepth \(track.bitsPerSample)")
            : nil
        if let sampleRate {
            rows.append(Row(field: .sampleRate, value: joined(sampleRate, depth)))
        }

        if let decoder = source.audioDecoder {
            rows.append(Row(field: .decoder, value: decoder))
        }

        if let output = audioDeliveryLabel(source.audioDelivery) {
            let bridge = source.telemetry?.audioBridgeBitrateMbps.map(formatter.megabits)
            rows.append(Row(field: .audioOutput, value: joined(output, bridge)))
        }

        if let objects = source.telemetry?.objectAudio, objects.objects > 0 {
            rows.append(Row(
                field: .objects,
                value: String(localized: "player.statistics.objects \(objects.activeObjects) \(objects.objects)"),
            ))
        }

        if track.bitrate > 0 {
            rows.append(Row(field: .bitrate, value: formatter.kilobits(Double(track.bitrate) / 1000)))
        }
        return rows
    }

    private static func subtitleRows(_ source: PlaybackStatisticsSource) -> [Row] {
        guard let renderer = source.subtitleRenderer else { return [] }
        var rows: [Row] = []
        if let codec = source.subtitleCodec, renderer != .burnedIn {
            rows.append(Row(field: .subtitleFormat, value: subtitleCodecLabel(codec)))
        }
        let rendering = switch renderer {
        case .burnedIn: String(localized: "player.statistics.subtitles.burnedIn")
        case .native: String(localized: "player.statistics.subtitles.native")
        case .styled: String(localized: "player.statistics.subtitles.styled")
        case .overlay: String(localized: "player.statistics.subtitles.overlay")
        }
        rows.append(Row(field: .subtitleRendering, value: rendering))
        return rows
    }

    private static func networkRows(_ source: PlaybackStatisticsSource, formatter: StatisticsFormatter) -> [Row] {
        let telemetry = source.telemetry
        var rows: [Row] = []

        switch (telemetry?.instantBitrateMbps, telemetry?.averageBitrateMbps) {
        case let (current?, average?):
            rows.append(Row(
                field: .mediaBitrate,
                value: String(
                    localized: "player.statistics.bitrate.currentAverage \(formatter.megabits(current)) \(formatter.megabits(average))",
                ),
            ))
        case let (current?, nil):
            rows.append(Row(field: .mediaBitrate, value: formatter.megabits(current)))
        case let (nil, average?):
            rows.append(Row(field: .mediaBitrate, value: formatter.megabits(average)))
        case (nil, nil):
            break
        }

        if let throughput = telemetry?.networkThroughputMbps {
            rows.append(Row(field: .throughput, value: formatter.megabits(throughput)))
        }

        // The software path leaves the native loaded-range metric nil; the engine's buffered position covers it.
        if let buffer = telemetry?.forwardBufferSeconds ?? source.bufferedAhead {
            rows.append(Row(field: .buffer, value: formatter.seconds(max(0, buffer))))
        }

        if let dropped = telemetry?.droppedFrameCount {
            rows.append(Row(field: .droppedFrames, value: formatter.integer(dropped)))
        }

        if let gap = telemetry?.avSyncGapMs {
            rows.append(Row(field: .avSync, value: formatter.milliseconds(gap)))
        }

        if let cached = telemetry?.cachedBytes, cached > 0 {
            rows.append(Row(field: .cache, value: formatter.bytes(cached)))
        }
        return rows
    }

    private static func routeLabel(_ route: VideoRoute) -> String? {
        switch route {
        case .none: nil
        case .remoteBypass: String(localized: "player.statistics.route.remoteBypass")
        case .loopback: String(localized: "player.statistics.route.loopback")
        case .software: String(localized: "player.statistics.route.software")
        case .audio: String(localized: "player.statistics.route.audio")
        }
    }

    /// AVPlayer decodes on the native routes, and the engine names no decoder there.
    private static func nativeDecoderLabel(_ route: VideoRoute) -> String? {
        switch route {
        case .remoteBypass, .loopback: "AVFoundation"
        case .none, .software, .audio: nil
        }
    }

    private static func audioDeliveryLabel(_ delivery: AudioDelivery) -> String? {
        switch delivery {
        case .none, .noAudioInSource: nil
        case .streamCopy: String(localized: "player.statistics.audioOutput.streamCopy")
        case .bridged: String(localized: "player.statistics.audioOutput.bridged")
        case .decoded: String(localized: "player.statistics.audioOutput.decoded")
        case .droppedNoPipeline: String(localized: "player.statistics.audioOutput.dropped")
        case .playerManaged: String(localized: "player.statistics.audioOutput.playerManaged")
        }
    }

    private static func dynamicRangeLabel(_ source: PlaybackStatisticsSource) -> String {
        var sourceLabel = videoFormatLabel(source.sourceVideoFormat)
        if source.sourceVideoFormat == .dolbyVision, let profile = source.dolbyVisionProfile {
            sourceLabel += " P\(profile)"
        }
        let presented = switch (source.dolbyVisionConversion, source.presentedVideoFormat) {
        case (.profile7ToProfile81, .dolbyVision): "Dolby Vision P8.1"
        case let (_, format): videoFormatLabel(format)
        }
        let sourceBase = videoFormatLabel(source.sourceVideoFormat)
        return presented == sourceBase ? sourceLabel : "\(sourceLabel) → \(presented)"
    }

    private static func videoFormatLabel(_ format: VideoFormat) -> String {
        switch format {
        case .sdr: "SDR"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .dolbyVision: "Dolby Vision"
        case .hlg: "HLG"
        }
    }

    private static func resolutionLabel(source: CGSize?, display: CGSize?) -> String? {
        let sourceLabel = source.flatMap(sizeLabel)
        let displayLabel = display.flatMap(sizeLabel)
        switch (sourceLabel, displayLabel) {
        case let (source?, display?) where source != display:
            return "\(source) → \(display)"
        case let (source?, _):
            return source
        case let (nil, display):
            return display
        }
    }

    private static func sizeLabel(_ size: CGSize) -> String? {
        guard size.width > 0, size.height > 0 else { return nil }
        return "\(Int(size.width.rounded()))×\(Int(size.height.rounded()))"
    }

    private static func frameRateLabel(nominal: Double?, observed: Double?, formatter: StatisticsFormatter) -> String? {
        let nominal = nominal.flatMap { $0 > 0 ? formatter.framesPerSecond($0) : nil }
        let observed = observed.flatMap { $0 > 0 ? $0 : nil }.map {
            String(localized: "player.statistics.frameRate.observed \(formatter.decimal($0, fractionLength: 1))")
        }
        guard nominal != nil || observed != nil else { return nil }
        return joined(nominal, observed)
    }

    private static func pixelFormatLabel(source: VideoStreamFormat?, decoded: DecodedVideoFormat?) -> String? {
        let format = decoded?.frame ?? source
        let depth = format?.bitDepth.map { String(localized: "player.statistics.bitDepth \($0)") }
        let pixel = joined(format?.pixelFormat, depth)
        let buffer = decoded?.pixelBufferLabel
        switch (pixel.isEmpty ? nil : pixel, buffer) {
        case let (pixel?, buffer?): return "\(pixel) → \(buffer)"
        case let (pixel?, nil): return pixel
        case let (nil, buffer): return buffer
        }
    }

    private static func channelsLabel(_ track: TrackInfo) -> String? {
        if let layout = track.channelLayout, !layout.isEmpty {
            return layout
        }
        guard track.channels > 0 else { return nil }
        return String(localized: "player.statistics.channels \(track.channels)")
    }

    private static func videoCodecLabel(_ codec: String) -> String {
        switch codec.lowercased() {
        case "h264": "H.264"
        case "hevc", "h265": "HEVC"
        case "av1": "AV1"
        case "vp9": "VP9"
        case "vp8": "VP8"
        case "mpeg2video": "MPEG-2"
        case "mpeg4": "MPEG-4"
        case "vc1": "VC-1"
        case let other: other.uppercased()
        }
    }

    private static func audioCodecLabel(_ track: TrackInfo) -> String {
        let codec = switch track.codec.lowercased() {
        case "truehd": "TrueHD"
        case "eac3": "E-AC-3"
        case "ac3": "AC-3"
        case "dts", "dca": "DTS"
        case "aac": "AAC"
        case "flac": "FLAC"
        case "opus": "Opus"
        case "vorbis": "Vorbis"
        case "mp3": "MP3"
        case "alac": "ALAC"
        case let other where other.hasPrefix("pcm"): "PCM"
        case let other: other.uppercased()
        }
        if let profile = track.profile, !profile.isEmpty {
            return "\(codec) (\(profile))"
        }
        return track.isAtmos ? "\(codec) (Atmos)" : codec
    }

    private static func subtitleCodecLabel(_ codec: String) -> String {
        switch codec.lowercased() {
        case "subrip", "srt": "SRT"
        case "ass", "ssa": "ASS"
        case "webvtt", "vtt": "WebVTT"
        case "hdmv_pgs_subtitle", "pgs", "pgssub": "PGS"
        case "dvd_subtitle", "dvdsub", "vobsub": "VobSub"
        case "dvb_subtitle", "dvbsub": "DVB"
        case "mov_text": "TX3G"
        case let other: other.uppercased()
        }
    }

    private static func containerLabel(_ format: String) -> String? {
        let primary = format.split(separator: ",").first.map(String.init) ?? format
        return switch primary {
        case "": nil
        case "matroska": "Matroska"
        case "mov": "MP4"
        case "mpegts": "MPEG-TS"
        case "hls": "HLS"
        case "avi": "AVI"
        case "webm": "WebM"
        case let other: other.uppercased()
        }
    }

    private static func joined(_ parts: String?...) -> String {
        parts.compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct StatisticsFormatter {
    let locale: Locale

    func decimal(_ value: Double, fractionLength: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionLength)).locale(locale))
    }

    func integer(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    func megabits(_ value: Double) -> String {
        String(localized: "player.statistics.unit.megabits \(decimal(value, fractionLength: value < 10 ? 2 : 1))")
    }

    func kilobits(_ value: Double) -> String {
        String(localized: "player.statistics.unit.kilobits \(decimal(value, fractionLength: 0))")
    }

    func kilohertz(_ value: Double) -> String {
        let fraction = value.rounded() == value ? 0 : 1
        return String(localized: "player.statistics.unit.kilohertz \(decimal(value, fractionLength: fraction))")
    }

    func framesPerSecond(_ value: Double) -> String {
        let fraction = abs(value - value.rounded()) < 0.0005 ? 0 : 3
        return String(localized: "player.statistics.unit.fps \(decimal(value, fractionLength: fraction))")
    }

    func seconds(_ value: Double) -> String {
        String(localized: "player.statistics.unit.seconds \(decimal(value, fractionLength: 1))")
    }

    func milliseconds(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return String(localized: "player.statistics.unit.milliseconds \(sign + decimal(value, fractionLength: 0))")
    }

    func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file).locale(locale))
    }
}
