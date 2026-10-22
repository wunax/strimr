import Foundation

extension SeerrMedia {
    var displayTitle: String {
        switch mediaType {
        case .tv, .person:
            name ?? title ?? ""
        case .movie, .none:
            title ?? name ?? ""
        }
    }

    var year: Int? {
        let date = mediaType == .tv ? firstAirDate : releaseDate
        guard let date, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

    var genreNames: [String] {
        genres?.compactMap(\.name).filter { !$0.isEmpty } ?? []
    }
}

extension MediaFactsFormatter {
    /// Same line as a library item: year, seasons or runtime, then the first two genres. Seerr has no content rating.
    static func facts(for media: SeerrMedia) -> MediaFacts {
        var tokens: [String] = []

        if let year = media.year {
            tokens.append(String(year))
        }
        switch media.mediaType {
        case .tv:
            if let count = media.numberOfSeasons, count > 0 {
                tokens.append(String(localized: "media.labels.seasonsCount \(count)"))
            }
        case .movie:
            if let runtime = media.runtime, runtime > 0 {
                tokens.append(TimeInterval(runtime * 60).mediaDurationText())
            }
        case .person, .none:
            break
        }
        tokens += media.genreNames.prefix(2)

        return MediaFacts(tokens: tokens)
    }
}

extension MediaRating {
    /// Seerr scores on the scales library items use: Rotten Tomatoes percentages become tenths, like Plex reports them.
    static func ratings(from ratings: SeerrMediaRatings?, voteAverage: Double?) -> [MediaRating] {
        var result: [MediaRating] = []
        if let score = ratings?.rt?.criticsScore {
            result.append(MediaRating(source: .rottenTomatoesCritic, value: Double(score) / 10))
        }
        if let score = ratings?.rt?.audienceScore {
            result.append(MediaRating(source: .rottenTomatoesAudience, value: Double(score) / 10))
        }
        if let score = ratings?.imdb?.criticsScore {
            result.append(MediaRating(source: .imdb, value: score))
        }
        if let voteAverage, voteAverage > 0 {
            result.append(MediaRating(source: .tmdb, value: voteAverage))
        }
        return result
    }
}
