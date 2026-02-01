import Foundation

enum SeerrMediaRequestType: Hashable {
    case standard
    case fourK

    var is4k: Bool {
        switch self {
        case .standard:
            false
        case .fourK:
            true
        }
    }

    var titleKey: String {
        switch self {
        case .standard:
            "seerr.request.type.standard"
        case .fourK:
            "seerr.request.type.fourK"
        }
    }

    var subtitleKey: String {
        switch self {
        case .standard:
            "seerr.request.type.standard.description"
        case .fourK:
            "seerr.request.type.fourK.description"
        }
    }
}
