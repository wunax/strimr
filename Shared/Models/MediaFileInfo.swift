import Foundation

enum MediaFileStreamKind: String, Hashable, Sendable {
    case video
    case audio
    case subtitle
    case other
}

struct MediaFileInfo: Hashable, Sendable {
    let versions: [MediaFileVersion]

    var firstVersion: MediaFileVersion? {
        versions.first
    }
}

struct MediaFileVersion: Hashable, Sendable {
    let id: String?
    let title: String?
    let container: String?
    let bitrateKbps: Int?
    let duration: TimeInterval?
    let width: Int?
    let height: Int?
    let aspectRatio: String?
    let videoResolution: String?
    let videoCodec: String?
    let videoProfile: String?
    let videoFrameRate: String?
    let audioCodec: String?
    let audioProfile: String?
    let audioChannels: Int?
    let parts: [MediaFilePart]
    let attachments: [MediaFileAttachment]

    var resolutionText: String? {
        if let videoResolution, !videoResolution.isEmpty {
            return videoResolution.uppercased()
        }
        if let width, let height {
            return "\(width) × \(height)"
        }
        return nil
    }

    var durationText: String? {
        duration?.mediaDurationText()
    }

    var totalSize: Int64? {
        let sizes = parts.compactMap(\.sizeBytes)
        guard !sizes.isEmpty else { return nil }
        return sizes.reduce(0, +)
    }

    var totalSizeText: String? {
        totalSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    var bitrateText: String? {
        bitrateKbps.map(Self.formatBitrate)
    }

    var primaryVideoStream: MediaFileStream? {
        parts.lazy.flatMap(\.streams).first { $0.kind == .video }
    }

    var primaryAudioStream: MediaFileStream? {
        parts.lazy.flatMap(\.streams).first { $0.kind == .audio }
    }

    var summaryLabels: [String] {
        let video = primaryVideoStream
        let audio = primaryAudioStream
        return [
            container?.uppercased(),
            resolutionText,
            video?.dynamicRange,
            videoCodec?.uppercased() ?? video?.codec?.uppercased(),
            audioCodec?.uppercased() ?? audio?.codec?.uppercased(),
            audio?.spatialFormat,
            totalSizeText,
            durationText,
        ].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
    }

    private nonisolated static func formatBitrate(_ value: Int) -> String {
        if value >= 1000 {
            return String(format: "%.1f Mbps", Double(value) / 1000)
        }
        return "\(value) kbps"
    }
}

struct MediaFilePart: Hashable, Sendable {
    let id: String?
    let path: String?
    let sizeBytes: Int64?
    let container: String?
    let duration: TimeInterval?
    let exists: Bool?
    let accessible: Bool?
    let streams: [MediaFileStream]

    var fileName: String? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var sizeText: String? {
        sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    var durationText: String? {
        duration?.mediaDurationText()
    }
}

struct MediaFileStream: Hashable, Sendable {
    let kind: MediaFileStreamKind
    let id: String?
    let index: Int?
    let title: String?
    let displayTitle: String?
    let codec: String?
    let codecTag: String?
    let profile: String?
    let language: String?
    let languageCode: String?
    let bitrateKbps: Int?
    let isDefault: Bool?
    let isForced: Bool?
    let isSelected: Bool?
    let isExternal: Bool?
    let isHearingImpaired: Bool?
    let width: Int?
    let height: Int?
    let frameRate: Double?
    let bitDepth: Int?
    let dynamicRange: String?
    let pixelFormat: String?
    let colorSpace: String?
    let colorTransfer: String?
    let aspectRatio: String?
    let channels: Int?
    let channelLayout: String?
    let sampleRate: Int?
    let spatialFormat: String?
    let subtitleFormat: String?
    let path: String?

    var headline: String {
        [displayTitle, title, language, codec]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? String(localized: "media.fileInfo.track")
    }

    var resolutionText: String? {
        guard let width, let height else { return nil }
        return "\(width) × \(height)"
    }

    var frameRateText: String? {
        guard let frameRate else { return nil }
        return "\(frameRate.formatted(.number.precision(.fractionLength(0 ... 3)))) fps"
    }

    var bitrateText: String? {
        guard let bitrateKbps else { return nil }
        if bitrateKbps >= 1000 {
            return String(format: "%.1f Mbps", Double(bitrateKbps) / 1000)
        }
        return "\(bitrateKbps) kbps"
    }

    var channelsText: String? {
        if let channelLayout, let channels {
            return "\(channelLayout) (\(channels) ch)"
        }
        if let channelLayout {
            return channelLayout
        }
        return channels.map { "\($0) ch" }
    }

    var sampleRateText: String? {
        guard let sampleRate else { return nil }
        if sampleRate % 1000 == 0 {
            return "\(sampleRate / 1000) kHz"
        }
        return "\(Double(sampleRate) / 1000) kHz"
    }
}

struct MediaFileAttachment: Hashable, Sendable {
    let index: Int?
    let fileName: String?
    let mimeType: String?
    let codec: String?
}
