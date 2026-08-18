import Foundation

enum MediaRatingSource: Hashable {
    case imdb
    case rottenTomatoesCritic
    case rottenTomatoesAudience
    case tmdb
    case jellyfinCommunity
    case jellyfinCritics

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

    var icon: MediaRatingIcon {
        switch self {
        case .imdb:
            .asset("imdb")
        case .rottenTomatoesCritic:
            .asset("rotten_tomatoes_critic")
        case .rottenTomatoesAudience:
            .asset("rotten_tomatoes_audience")
        case .tmdb:
            .asset("tmdb")
        case .jellyfinCommunity:
            .system("star.fill")
        case .jellyfinCritics:
            .asset("rotten_tomatoes_critic")
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
        case .jellyfinCommunity:
            String(localized: "media.rating.jellyfinCommunity")
        case .jellyfinCritics:
            String(localized: "media.rating.jellyfinCritics")
        }
    }
}

enum MediaRatingIcon: Hashable {
    case asset(String)
    case system(String)
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

    init(source: MediaRatingSource, value: Double) {
        self.source = source
        self.value = value
    }

    var formattedValue: String {
        switch source {
        case .jellyfinCritics:
            String(format: "%.0f%%", value)
        default:
            String(format: "%.1f", value)
        }
    }

    var accessibilityLabel: String {
        "\(source.accessibilityName), \(formattedValue)"
    }
}
