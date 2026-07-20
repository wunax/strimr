import Foundation

enum MediaRatingSource: Hashable {
    case imdb
    case rottenTomatoesCritic
    case rottenTomatoesAudience
    case tmdb

    init?(imageIdentifier: String) {
        switch imageIdentifier {
        case "imdb://image.rating":
            self = .imdb
        case "rottentomatoes://image.rating.ripe":
            self = .rottenTomatoesCritic
        case "rottentomatoes://image.rating.upright":
            self = .rottenTomatoesAudience
        case "themoviedb://image.rating":
            self = .tmdb
        default:
            return nil
        }
    }

    var assetName: String {
        switch self {
        case .imdb:
            "imdb"
        case .rottenTomatoesCritic:
            "rotten_tomatoes_critic"
        case .rottenTomatoesAudience:
            "rotten_tomatoes_audience"
        case .tmdb:
            "tmdb"
        }
    }

    var accessibilityName: String {
        switch self {
        case .imdb:
            String(localized: "media.rating.imdb")
        case .rottenTomatoesCritic:
            String(localized: "media.rating.rottenTomatoesCritic")
        case .rottenTomatoesAudience:
            String(localized: "media.rating.rottenTomatoesAudience")
        case .tmdb:
            String(localized: "media.rating.tmdb")
        }
    }
}

struct MediaRating: Hashable {
    let source: MediaRatingSource
    let value: Double

    init?(imageIdentifier: String, value: Double) {
        guard let source = MediaRatingSource(imageIdentifier: imageIdentifier) else {
            return nil
        }

        self.source = source
        self.value = value
    }

    var formattedValue: String {
        String(format: "%.1f", value)
    }

    var accessibilityLabel: String {
        "\(source.accessibilityName), \(formattedValue)"
    }
}
