import CoreGraphics
import Foundation

enum TMDBImageService {
    enum Size: String {
        case w92
        case w45
        case w154
        case w185
        case w342
        case w500
        case w780
        case w300
        case w1280
        case h632
        case original
    }

    private static let baseURL = URL(string: "https://image.tmdb.org/t/p/")

    static func imageURL(path: String?, size: Size) -> URL? {
        guard let path, !path.isEmpty, let baseURL else {
            return nil
        }

        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return baseURL.appendingPathComponent(size.rawValue + normalizedPath)
    }

    static func posterURL(path: String?, width: CGFloat?) -> URL? {
        imageURL(path: path, size: size(forWidth: width))
    }

    static func backdropURL(path: String?, width: CGFloat?) -> URL? {
        imageURL(path: path, size: backdropSize(forWidth: width))
    }

    static func profileURL(path: String?, width: CGFloat?, height: CGFloat? = nil) -> URL? {
        imageURL(path: path, size: profileSize(forWidth: width, height: height))
    }

    private static func size(forWidth width: CGFloat?) -> Size {
        guard let width else {
            return .w342
        }

        switch width {
        case ..<100:
            return .w92
        case ..<160:
            return .w154
        case ..<200:
            return .w185
        case ..<360:
            return .w342
        case ..<560:
            return .w500
        case ..<800:
            return .w780
        default:
            return .original
        }
    }

    private static func backdropSize(forWidth width: CGFloat?) -> Size {
        guard let width else {
            return .w780
        }

        switch width {
        case ..<500:
            return .w300
        case ..<1200:
            return .w780
        case ..<1400:
            return .w1280
        default:
            return .original
        }
    }

    private static func profileSize(forWidth width: CGFloat?, height: CGFloat?) -> Size {
        if let height, height >= 632 {
            return .h632
        }

        guard let width else {
            return .w185
        }

        switch width {
        case ..<80:
            return .w45
        case ..<220:
            return .w185
        default:
            return .h632
        }
    }
}
