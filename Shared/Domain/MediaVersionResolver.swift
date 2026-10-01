import Foundation
import OSLog

struct MediaVersionPreference: Codable, Hashable, Sendable {
    /// Only meaningful for the item the choice was made on; other items match by signature.
    let versionID: String?
    let signature: String
    let updatedAt: Date
}

enum MediaVersionRequest: Hashable, Sendable {
    case automatic
    case preferred(MediaVersionPreference)
    case explicit(versionID: String)
}

/// `<height>:<video codec>:<container>:<dynamic range>`, e.g. `2160:hevc:mkv:dv`.
nonisolated struct MediaVersionSignature: Hashable, Sendable {
    let height: String
    let videoCodec: String
    let container: String
    let dynamicRange: String

    init(height: String, videoCodec: String, container: String, dynamicRange: String) {
        self.height = height
        self.videoCodec = videoCodec
        self.container = container
        self.dynamicRange = dynamicRange
    }

    init(_ rawValue: String) {
        var components = rawValue.lowercased().split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        components += Array(repeating: "", count: max(0, 4 - components.count))
        height = components[0]
        videoCodec = components[1]
        container = components[2]
        dynamicRange = components[3]
    }

    var rawValue: String {
        [height, videoCodec, container, dynamicRange].joined(separator: ":")
    }

    static let heightTiers = [480, 720, 1080, 2160, 4320]

    static func heightTier(width: Int?, height: Int?, videoResolution: String?) -> Int? {
        // Width catches letterboxed encodes such as 1920×800, which belong to the 1080 tier.
        let fromHeight = height.flatMap { value -> Int? in
            guard value > 0 else { return nil }
            switch value {
            case 3240...: return 4320
            case 1800...: return 2160
            case 900...: return 1080
            case 600...: return 720
            default: return 480
            }
        }
        let fromWidth = width.flatMap { value -> Int? in
            guard value > 0 else { return nil }
            switch value {
            case 6400...: return 4320
            case 3200...: return 2160
            case 1600...: return 1080
            case 1100...: return 720
            default: return nil
            }
        }
        if fromHeight != nil || fromWidth != nil {
            return max(fromHeight ?? 0, fromWidth ?? 0)
        }
        return videoResolution.flatMap(heightTier(videoResolution:))
    }

    private static func heightTier(videoResolution: String) -> Int? {
        let value = videoResolution.lowercased().trimmingCharacters(in: .whitespaces)
        switch value {
        case "sd", "480", "480p", "576", "576p": return 480
        case "720", "720p", "hd": return 720
        case "1080", "1080p", "1080i", "fhd": return 1080
        case "4k", "2160", "2160p", "uhd": return 2160
        case "8k", "4320", "4320p": return 4320
        default:
            let digits = value.prefix { $0.isNumber }
            guard let height = Int(digits) else { return nil }
            return heightTier(width: nil, height: height, videoResolution: nil)
        }
    }

    static func normalizedVideoCodec(_ codec: String?) -> String {
        let value = codec?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        switch value {
        case "h265", "x265", "hvc1", "hev1": return "hevc"
        case "avc", "avc1", "x264": return "h264"
        default: return value
        }
    }

    static func normalizedContainer(_ container: String?) -> String {
        // Jellyfin reports demuxer lists such as "mov,mp4,m4a,3gp,3g2,mj2".
        container?.lowercased().split(separator: ",").first.map {
            $0.trimmingCharacters(in: .whitespaces)
        } ?? ""
    }

    static func normalizedDynamicRange(_ dynamicRange: String?) -> String {
        let value = dynamicRange?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        if value.hasPrefix("dolby vision") || value.hasPrefix("dovi") {
            return "dv"
        }
        return value.replacingOccurrences(of: " ", with: "")
    }
}

extension MediaFileVersion {
    var signatureComponents: MediaVersionSignature {
        let video = primaryVideoStream
        let tier = MediaVersionSignature.heightTier(
            width: width ?? video?.width,
            height: height ?? video?.height,
            videoResolution: videoResolution,
        )
        let dynamicRange: String = if let range = video?.dynamicRange, !range.isEmpty {
            MediaVersionSignature.normalizedDynamicRange(range)
        } else {
            // Providers only report a dynamic range for HDR; a known video stream without one is SDR.
            video == nil ? "" : "sdr"
        }
        return MediaVersionSignature(
            height: tier.map(String.init) ?? "",
            videoCodec: MediaVersionSignature.normalizedVideoCodec(videoCodec ?? video?.codec),
            container: MediaVersionSignature.normalizedContainer(container),
            dynamicRange: dynamicRange,
        )
    }

    var signature: String {
        signatureComponents.rawValue
    }

    func matchesVersionID(_ versionID: String) -> Bool {
        // Jellyfin compares source ids case-insensitively.
        id?.caseInsensitiveCompare(versionID) == .orderedSame
    }
}

enum MediaVersionResolver {
    private static let logger = Logger(subsystem: "Strimr", category: "MediaVersion")

    /// Picks the version to play: explicit choice, then preference (id, then signature), then the provider default.
    /// Falls back to the first available version when the pick is unavailable; returns nil when none is.
    static func resolve(
        _ request: MediaVersionRequest,
        in versions: [MediaFileVersion],
        default defaultVersion: ([MediaFileVersion]) -> MediaFileVersion?,
    ) -> MediaFileVersion? {
        guard !versions.isEmpty else { return nil }

        switch request {
        case let .explicit(versionID):
            if let match = versions.first(where: { $0.matchesVersionID(versionID) && $0.isAvailable }) {
                return match
            }
            logger.info("Requested version is missing or unavailable, using default")
        case let .preferred(preference):
            if let versionID = preference.versionID,
               let match = versions.first(where: { $0.matchesVersionID(versionID) && $0.isAvailable })
            {
                return match
            }
            if let match = bestMatch(for: preference.signature, in: versions) {
                return match
            }
        case .automatic:
            break
        }

        let fallback = defaultVersion(versions)
        if let fallback, fallback.isAvailable {
            return fallback
        }
        let firstAvailable = versions.first(where: \.isAvailable)
        if firstAvailable != nil {
            logger.info("Default version is unavailable, falling back to the first available version")
        }
        return firstAvailable
    }

    /// Signature matching by decreasing precision; the first tier with a match wins.
    static func bestMatch(for signature: String, in versions: [MediaFileVersion]) -> MediaFileVersion? {
        let preferred = MediaVersionSignature(signature)
        let candidates = versions.filter(\.isAvailable)
        let tiers: [(MediaVersionSignature, MediaVersionSignature) -> Bool] = [
            { $0 == $1 },
            { $0.height == $1.height && $0.videoCodec == $1.videoCodec && $0.dynamicRange == $1.dynamicRange },
            { $0.height == $1.height && $0.videoCodec == $1.videoCodec },
            { $0.height == $1.height },
        ]

        for (index, matches) in tiers.enumerated() {
            // Loose tiers need a known height, otherwise they would match anything with an unknown height.
            if index > 0, preferred.height.isEmpty {
                break
            }
            let matching = candidates.filter { matches(preferred, $0.signatureComponents) }
            // An "Original quality" Plex optimization can share the source's exact signature.
            if let match = matching.first(where: { !$0.isOptimized }) ?? matching.first {
                return match
            }
        }
        return nil
    }
}
