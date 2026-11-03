import Foundation
import AetherEngine
@testable import Strimr
import Testing

@MainActor
struct LiveLoadOptionsTests {
    @Test func `keeps a local timeshift on the loopback`() {
        let options = LiveLoadOptions.make(
            nativeRemoteHLS: false,
            captureDuration: 120,
            isInterlaced: false,
            routesAudioToAirPlay: false,
            preferredLanguages: [],
        )

        #expect(options.dvrWindowSeconds == 1800)
        #expect(options.probesize == 5_000_000)
        #expect(options.maxAnalyzeDuration == 5_000_000)
    }

    @Test func `uses the server capture on AVPlayer's route`() {
        let plex = LiveLoadOptions.make(
            nativeRemoteHLS: true,
            captureDuration: 600,
            isInterlaced: false,
            routesAudioToAirPlay: false,
            preferredLanguages: [],
        )
        let jellyfin = LiveLoadOptions.make(
            nativeRemoteHLS: true,
            captureDuration: nil,
            isInterlaced: false,
            routesAudioToAirPlay: false,
            preferredLanguages: [],
        )

        #expect(plex.dvrWindowSeconds == 600)
        #expect(jellyfin.dvrWindowSeconds == nil)
        #expect(plex.probesize == nil)
    }

    @Test func `decodes interlaced channels in software`() {
        let interlaced = LiveLoadOptions.make(
            nativeRemoteHLS: false,
            captureDuration: nil,
            isInterlaced: true,
            routesAudioToAirPlay: false,
            preferredLanguages: [],
        )
        let progressive = LiveLoadOptions.make(
            nativeRemoteHLS: false,
            captureDuration: nil,
            isInterlaced: false,
            routesAudioToAirPlay: false,
            preferredLanguages: [],
        )

        #expect(interlaced.preferredDecodePath == .software)
        #expect(progressive.preferredDecodePath == .automatic)
    }

    @Test func `holds the join while audio goes to AirPlay`() {
        let options = LiveLoadOptions.make(
            nativeRemoteHLS: false,
            captureDuration: nil,
            isInterlaced: false,
            routesAudioToAirPlay: true,
            preferredLanguages: [],
        )

        #expect(!options.startsImmediately)
        #expect(!options.autoplay)
    }

    @Test func `turns preferred languages into unique language codes`() {
        #expect(LiveLoadOptions.languageCodes(from: ["fr-FR", "fr-CA", "en-US"]) == ["fr", "en"])
    }

    @Test func `only demux failures move to the server transcode`() {
        let demux = NSError(domain: "AetherEngine.DemuxerError", code: 1, userInfo: ["AetherFFmpegErrorCode": -1_094_995_529])
        let network = NSError(domain: "AetherEngine.DemuxerError", code: 2, userInfo: ["AetherFFmpegErrorCode": -60])

        #expect(LiveLoadOptions.isDemuxFailure(demux))
        #expect(LiveLoadOptions.isDemuxFailure(AetherEngineError.noVideoStream))
        #expect(!LiveLoadOptions.isDemuxFailure(network))
        #expect(!LiveLoadOptions.isDemuxFailure(CancellationError()))
        #expect(!LiveLoadOptions.isDemuxFailure(URLError(.timedOut)))
    }
}
