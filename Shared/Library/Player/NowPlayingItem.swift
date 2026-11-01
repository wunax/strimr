import Foundation
import MediaPlayer

/// Fields beyond the card itself, for whatever reads the system's Now Playing info (remote apps, HomeKit,
/// the Companion protocol). The system only documents some keys, see `NowPlayingItem.identityInfo`.
struct NowPlayingDetails: Equatable {
    var contentIdentifier: String?
    /// Zero-based position in the play queue.
    var queueIndex: Int?
    var queueCount: Int?
    var chapterCount: Int?
    var intro: ClosedRange<TimeInterval>?
    var credits: ClosedRange<TimeInterval>?
    var nextTitle: String?

    /// The one-based chapter holding `time`, nil outside every chapter.
    static func chapterNumber(at time: TimeInterval, in chapters: [MediaChapter]) -> Int? {
        chapters.firstIndex { $0.contains(time: time) }.map { $0 + 1 }
    }
}

/// What the system Now Playing card shows for the current media.
struct NowPlayingItem {
    var details = NowPlayingDetails()
    let title: String
    let subtitle: String?
    let artworkPath: String?
    let artworkService: (any MediaArtworkService)?
    let skipBackwardSeconds: Double
    let skipForwardSeconds: Double

    init(
        title: String,
        subtitle: String? = nil,
        artworkPath: String? = nil,
        artworkService: (any MediaArtworkService)? = nil,
        skipBackwardSeconds: Double,
        skipForwardSeconds: Double,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artworkPath = artworkPath
        self.artworkService = artworkService
        self.skipBackwardSeconds = skipBackwardSeconds
        self.skipForwardSeconds = skipForwardSeconds
    }

    init?(
        media: MediaItem?,
        artworkService: (any MediaArtworkService)?,
        skipBackwardSeconds: Int,
        skipForwardSeconds: Int,
    ) {
        guard let media else { return nil }
        let subtitle: String? = if case .episode = media.type {
            [media.grandparentTitle, media.tertiaryLabel]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        } else {
            nil
        }
        self.init(
            title: media.title,
            subtitle: subtitle?.isEmpty == false ? subtitle : nil,
            artworkPath: media.preferredThumbPath,
            artworkService: artworkService,
            skipBackwardSeconds: Double(skipBackwardSeconds),
            skipForwardSeconds: Double(skipForwardSeconds),
        )
    }

    /// Identity keys only: position, duration and rate come from the player.
    ///
    /// Documented keys: content identifier, queue index and count, chapter count and number (one-based here).
    /// Chapters and the queue are what tvOS and remote apps can show. The `strimr.*` keys are not documented, so the system may
    /// keep them in the dictionary without exposing them to anything.
    func identityInfo(artwork: MPMediaItemArtwork?, isLive: Bool, chapterNumber: Int? = nil) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
        ]
        if let subtitle {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        if let id = details.contentIdentifier {
            info[MPNowPlayingInfoPropertyExternalContentIdentifier] = id
        }
        if let index = details.queueIndex, let count = details.queueCount {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = count
        }
        if let count = details.chapterCount {
            info[MPNowPlayingInfoPropertyChapterCount] = count
            if let chapterNumber {
                info[MPNowPlayingInfoPropertyChapterNumber] = chapterNumber
            }
        }
        if let intro = details.intro {
            info["strimr.intro"] = [intro.lowerBound, intro.upperBound]
        }
        if let credits = details.credits {
            info["strimr.credits"] = [credits.lowerBound, credits.upperBound]
        }
        if let nextTitle = details.nextTitle {
            info["strimr.nextTitle"] = nextTitle
        }
        return info
    }
}

enum NowPlayingPlayback {
    /// The rate the system extrapolates the elapsed time with.
    static func rate(isPlaying: Bool, isBuffering: Bool, requestedRate: Float) -> Double {
        guard isPlaying, !isBuffering else { return 0 }
        return Double(requestedRate > 0 ? requestedRate : 1)
    }

    /// Whether the published position drifted from what the system extrapolates, after a seek or a stall.
    static func hasDrifted(
        position: Double,
        publishedElapsed: Double,
        publishedRate: Double,
        secondsSincePublish: TimeInterval,
    ) -> Bool {
        let expected = publishedElapsed + publishedRate * secondsSincePublish
        return abs(position - expected) > 2
    }
}
