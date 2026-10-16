import Foundation

nonisolated enum ExternalPlayerTemplateError: Error, Equatable {
    case missingURL
    case unknownVariable(String)
    case invalidURL
}

/// Builds a player URL from a template such as `myplayer://play?url={url}`.
nonisolated enum ExternalPlayerTemplate {
    private static let knownVariables: Set<String> = ["url", "title", "position", "callback"]
    /// Unreserved characters only: the stream URL carries its own query, which must stay a single value.
    private static let allowedValueCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~",
    )

    static func validate(_ template: String) throws(ExternalPlayerTemplateError) {
        let target = ExternalPlaybackTarget(
            url: URL(string: "http://localhost/video")!,
            title: "",
            item: MediaIdentity(server: ServerIdentity(provider: .plex, id: "server"), itemID: "item"),
            duration: nil,
        )
        _ = try render(template, target: target)
    }

    static func render(
        _ template: String,
        target: ExternalPlaybackTarget,
    ) throws(ExternalPlayerTemplateError) -> URL {
        let variablePattern = /\{([^{}]*)\}/
        let variables = template.matches(of: variablePattern).map { String($0.output.1) }
        if let unknown = variables.first(where: { !knownVariables.contains($0) }) {
            throw .unknownVariable(unknown)
        }
        guard variables.contains("url") else { throw .missingURL }

        let values = [
            "url": target.url.absoluteString,
            "title": target.title,
            "position": String(Int(max(0, target.startPosition))),
            "callback": ExternalPlaybackCallback.url(for: target).absoluteString,
        ]
        let rendered = template.replacing(variablePattern) { match in
            encode(values[String(match.output.1)] ?? "")
        }
        guard let result = URL(string: rendered), let scheme = result.scheme, !scheme.isEmpty else {
            throw .invalidURL
        }
        return result
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowedValueCharacters) ?? ""
    }
}
