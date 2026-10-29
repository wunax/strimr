import Foundation
import MediaPlayer

/// What the system Now Playing card shows for the current media.
struct NowPlayingItem {
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
    func identityInfo(artwork: MPMediaItemArtwork?, isLive: Bool) -> [String: Any] {
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
