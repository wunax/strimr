import Observation
import SwiftUI

enum ExternalPlayerOption: Hashable, Identifiable {
    case builtIn
    case known(ExternalPlayerID)
    case custom

    var id: String {
        switch self {
        case .builtIn: "builtIn"
        case let .known(player): player.rawValue
        case .custom: "custom"
        }
    }
}

@MainActor
@Observable
final class CustomExternalPlayerFormModel {
    var name: String
    var template: String

    init(player: CustomExternalPlayer?) {
        name = player?.name ?? ""
        template = player?.template ?? ""
    }

    var player: CustomExternalPlayer {
        CustomExternalPlayer(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            template: template.trimmingCharacters(in: .whitespacesAndNewlines),
        )
    }

    var canSave: Bool {
        player.isValid
    }

    /// Nil while the template is empty, so the form does not open on an error.
    var templateError: String? {
        let template = player.template
        guard !template.isEmpty else { return nil }
        do {
            try ExternalPlayerTemplate.validate(template)
            return nil
        } catch {
            switch error {
            case .missingURL:
                return String(localized: "settings.playback.externalPlayer.custom.error.missingURL")
            case let .unknownVariable(name):
                return String(localized: "settings.playback.externalPlayer.custom.error.unknownVariable \(name)")
            case let .misplacedListVariable(name):
                return String(localized: "settings.playback.externalPlayer.custom.error.misplacedListVariable \(name)")
            case .invalidURL:
                return String(localized: "settings.playback.externalPlayer.custom.error.invalidURL")
            }
        }
    }
}
