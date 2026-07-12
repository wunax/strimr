import Foundation
import Observation

@MainActor
@Observable
final class TopShelfDeepLinkRouter {
    struct Action: Equatable {
        enum Kind: Equatable {
            case display
            case play
        }

        let kind: Kind
        let ratingKey: String
        let type: PlexItemType
    }

    private(set) var pendingAction: Action?

    func receive(_ url: URL) {
        guard url.scheme == "strimr",
              let host = url.host,
              let kind: Action.Kind = switch host
        {
        case "media": .display
        case "play": .play
        default: nil
        },
            let ratingKey = url.pathComponents.dropFirst().first,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let typeValue = components.queryItems?.first(where: { $0.name == "type" })?.value,
            let type = PlexItemType(rawValue: typeValue)
        else {
            return
        }

        pendingAction = Action(kind: kind, ratingKey: ratingKey, type: type)
    }

    func clear(_ action: Action) {
        guard pendingAction == action else { return }
        pendingAction = nil
    }
}
