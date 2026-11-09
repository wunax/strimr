import AetherEngine
import AVFoundation
import Foundation

/// Engine options of a Live TV load, derived from the source the server handed out.
struct LiveLoadOptions: Equatable {
    static let localDVRWindowSeconds: TimeInterval = 1800
    static let probesize: Int64 = 5_000_000
    static let maxAnalyzeDuration: Int64 = 5_000_000

    var route: LiveTVPlaybackRoute?
    var nativeRemoteHLS: Bool
    var dvrWindowSeconds: TimeInterval?
    var preferredDecodePath: DecodePath
    var probesize: Int64?
    var maxAnalyzeDuration: Int64?
    var preferredAudioLanguages: [String]
    var startsImmediately: Bool
    var autoplay: Bool

    static func make(
        route: LiveTVPlaybackRoute? = nil,
        nativeRemoteHLS: Bool,
        captureDuration: TimeInterval?,
        isInterlaced: Bool,
        routesAudioToAirPlay: Bool,
        preferredLanguages: [String],
    ) -> LiveLoadOptions {
        LiveLoadOptions(
            route: route,
            nativeRemoteHLS: nativeRemoteHLS,
            // AVPlayer seeks inside the server's capture on its own route; the loopback keeps its own history.
            dvrWindowSeconds: nativeRemoteHLS
                ? captureDuration.flatMap { $0 > 0 ? $0 : nil }
                : localDVRWindowSeconds,
            preferredDecodePath: isInterlaced && !nativeRemoteHLS ? .software : .automatic,
            probesize: nativeRemoteHLS ? nil : probesize,
            maxAnalyzeDuration: nativeRemoteHLS ? nil : maxAnalyzeDuration,
            preferredAudioLanguages: languageCodes(from: preferredLanguages),
            // AirPlay needs the route settled before the first frame, or the join stalls on the receiver.
            startsImmediately: !routesAudioToAirPlay,
            autoplay: !routesAudioToAirPlay,
        )
    }

    static var routesAudioToAirPlay: Bool {
        #if os(macOS)
            false
        #else
            AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
        #endif
    }

    static func languageCodes(from identifiers: [String]) -> [String] {
        var seen: Set<String> = []
        return identifiers.compactMap { identifier in
            let code = Locale(identifier: identifier).language.languageCode?.identifier
                ?? identifier.split(separator: "-").first.map(String.init)
            guard let code, !code.isEmpty, seen.insert(code).inserted else { return nil }
            return code
        }
    }

    /// The engine could not read the stream itself, as opposed to the network or the server failing.
    static func isDemuxFailure(_ error: Error) -> Bool {
        if error.isCancellation || error.isTransportFailure {
            return false
        }
        if let error = error as? AetherEngineError {
            switch error {
            case .noVideoStream, .noAudioStream: return true
            default: return false
            }
        }
        let error = error as NSError
        guard error.domain == "AetherEngine.DemuxerError" else { return false }
        guard let code = error.userInfo["AetherFFmpegErrorCode"] as? Int else { return true }
        return !networkErrorCodes.contains(code)
    }

    /// FFmpeg's `AVERROR(errno)` for timeouts, refused or reset connections and broken pipes.
    private static let networkErrorCodes: Set<Int> = [-5, -32, -50, -51, -54, -57, -60, -61, -65]
}
