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
        let provider: MediaProvider
        let serverIdentifier: String?
        let ratingKey: String
        let type: MediaKind
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
            let type = MediaKind(rawValue: typeValue)
                ?? (typeValue == "show" ? .series : nil)
        else {
            return
        }
        let provider = components.queryItems?
            .first(where: { $0.name == "provider" })?
            .value
            .flatMap { MediaProvider(rawValue: $0) } ?? .plex

        pendingAction = Action(
            kind: kind,
            provider: provider,
            serverIdentifier: components.queryItems?.first(where: { $0.name == "server" })?.value,
            ratingKey: ratingKey,
            type: type
        )
    }

    func clear(_ action: Action) {
        guard pendingAction == action else { return }
        pendingAction = nil
    }
}
