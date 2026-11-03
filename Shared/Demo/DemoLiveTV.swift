#if DEBUG
    import Foundation

    /// A made-up broadcast lineup for the demo server, enabled with `-DemoLiveTVChannels <count>`: enough channels
    /// and programs to exercise the guide at scale without a tuner.
    struct DemoLiveTV {
        static var channelCount: Int {
            UserDefaults.standard.integer(forKey: "DemoLiveTVChannels")
        }

        /// `-DemoLiveTVSection guide` opens the guide instead of the remembered section.
        static var section: String? {
            UserDefaults.standard.string(forKey: "DemoLiveTVSection")
        }

        let channels: [LiveTVChannel]
        private let titles: [MediaItem]

        init(channelCount: Int, titles: [MediaItem]) {
            self.titles = titles
            channels = (1 ... max(channelCount, 1)).map { number in
                LiveTVChannel(
                    providerID: "demo-channel-\(number)",
                    title: "Demo \(number)",
                    callSign: nil,
                    number: String(number),
                    thumbPath: nil,
                    artPath: nil,
                    lineupID: nil,
                    dvrID: nil,
                    isHD: true,
                    isFavorite: number % 17 == 0,
                )
            }
        }

        func programs(from start: Date, to end: Date) -> [LiveTVProgram] {
            guard !titles.isEmpty else { return [] }
            let categories: [Set<LiveTVCategory>] = [[.movie], [.series], [.sports], [.news], [.kids], []]
            return channels.enumerated().flatMap { index, channel -> [LiveTVProgram] in
                // Each channel has its own rhythm, so program edges do not line up across rows.
                let length = TimeInterval([20, 30, 45, 60, 90, 120][index % 6] * 60)
                let phase = TimeInterval((index * 7) % 30) * 60
                var slot = floor((start.timeIntervalSince1970 - phase) / length) * length + phase
                var result: [LiveTVProgram] = []
                while slot < end.timeIntervalSince1970 {
                    let order = Int(slot / length) + index
                    let title = titles[abs(order) % titles.count]
                    result.append(LiveTVProgram(
                        id: "\(channel.providerID)-\(Int(slot))",
                        channelID: channel.providerID,
                        channelIdentity: channel.identity,
                        title: title.title,
                        seriesTitle: nil,
                        summary: title.summary,
                        startDate: Date(timeIntervalSince1970: slot),
                        endDate: Date(timeIntervalSince1970: slot + length),
                        thumbPath: title.artPath,
                        artPath: title.artPath,
                        seasonNumber: nil,
                        episodeNumber: nil,
                        isLive: index % 9 == 0,
                        isPremiere: order % 11 == 0,
                        recordingID: nil,
                        seriesRecordingID: nil,
                        recordingStatus: nil,
                        providerGUID: nil,
                        categories: categories[index % categories.count],
                    ))
                    slot += length
                }
                return result
            }
        }
    }

    /// Plays the demo clip for any channel, so the live player can be shown without a tuner.
    @MainActor
    final class DemoLiveTVPlaybackSession: LiveTVPlaybackSession {
        let channel: LiveTVChannel
        let backgroundPolicy = LiveTVBackgroundPolicy.stopAndExit
        let captureRange: LiveTVCaptureRange? = nil
        private let clip: URL

        init(channel: LiveTVChannel, clip: URL) {
            self.channel = channel
            self.clip = clip
        }

        func source(offsetFromCaptureStart _: TimeInterval?) async throws -> LiveTVPlaybackSource {
            LiveTVPlaybackSource(
                url: clip,
                httpHeaders: [:],
                program: nil,
                captureRange: nil,
                nativeRemoteHLS: false,
                route: .directPlay,
            )
        }

        func report(position _: TimeInterval, isPaused _: Bool) async throws -> LiveTVCaptureRange? {
            nil
        }

        func recover() async throws -> any LiveTVPlaybackSession {
            self
        }

        func fallback() async throws -> (any LiveTVPlaybackSession)? {
            nil
        }

        func stop() async {}
    }
#endif
