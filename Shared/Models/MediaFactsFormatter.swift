import Foundation

struct MediaFacts: Equatable {
    var tokens: [String]
    var contentRating: String?

    var isEmpty: Bool {
        tokens.isEmpty && contentRating == nil
    }
}

/// Facts that fit on one line under a title: episode number, year, edition, seasons or runtime, then the first two
/// genres.
/// The content rating is kept apart because it is drawn as a badge.
enum MediaFactsFormatter {
    /// - Parameter namesStandardEdition: names the regular cut "Standard", for titles known to have other editions.
    static func facts(
        for media: MediaItem,
        seasonCount: Int? = nil,
        namesStandardEdition: Bool = false,
    ) -> MediaFacts {
        var tokens: [String] = []

        if media.type == .episode, let episodeLabel = media.tertiaryLabel {
            tokens.append(episodeLabel)
        }
        if let year = media.year {
            tokens.append(String(year))
        }
        if media.editionTitle != nil || namesStandardEdition {
            tokens.append(media.editionLabel)
        }
        switch media.type {
        case .series:
            if let count = seasonCount ?? listedSeasonCount(of: media), count > 0 {
                tokens.append(String(localized: "media.labels.seasonsCount \(count)"))
            }
        case .movie, .episode, .clip:
            if let duration = media.duration, duration >= 60 {
                tokens.append(duration.mediaDurationText())
            }
        case .season, .collection, .playlist, .folder, .unknown:
            break
        }
        tokens += media.genres.prefix(2)

        let rating = media.contentRating?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MediaFacts(tokens: tokens, contentRating: rating?.isEmpty == false ? rating : nil)
    }

    /// Jellyfin may fill `childCount` with the episode count, so only Plex's is trusted as a season count.
    private static func listedSeasonCount(of media: MediaItem) -> Int? {
        media.provider == .plex ? media.childCount : nil
    }
}

enum RemainingTimeFormatter {
    /// "23 min left" from the runtime and resume position, rounded to the minute; nil without progress.
    static func text(duration: TimeInterval?, viewOffset: TimeInterval?) -> String? {
        shortText(duration: duration, viewOffset: viewOffset)
            .map { String(localized: "media.labels.remaining \($0)") }
    }

    /// Just the time left, "23 min", for places that already say it is a resume.
    static func shortText(duration: TimeInterval?, viewOffset: TimeInterval?) -> String? {
        guard let duration, let viewOffset, viewOffset > 0, duration > viewOffset else { return nil }
        let minutes = max(1, Int(((duration - viewOffset) / 60).rounded()))
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

extension MediaItem {
    var remainingTimeText: String? {
        RemainingTimeFormatter.text(duration: duration, viewOffset: viewOffset)
    }

    var shortRemainingTimeText: String? {
        RemainingTimeFormatter.shortText(duration: duration, viewOffset: viewOffset)
    }
}
