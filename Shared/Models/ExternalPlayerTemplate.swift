import Foundation

nonisolated enum ExternalPlayerTemplateError: Error, Equatable {
    case missingURL
    case unknownVariable(String)
    case invalidURL
}

/// Builds a player URL from a template such as `myplayer://play?url={url}`.
nonisolated enum ExternalPlayerTemplate {
    static let callbackURL = "strimr://x-callback-url/playbackDidFinish"

    private static let knownVariables: Set<String> = ["url", "title", "callback"]
    /// Unreserved characters only: the stream URL carries its own query, which must stay a single value.
    private static let allowedValueCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~",
    )

    static func validate(_ template: String) throws(ExternalPlayerTemplateError) {
        _ = try render(template, url: URL(string: "http://localhost/video")!, title: "")
    }

    static func render(_ template: String, url: URL, title: String) throws(ExternalPlayerTemplateError) -> URL {
        let variablePattern = /\{([^{}]*)\}/
        let variables = template.matches(of: variablePattern).map { String($0.output.1) }
        if let unknown = variables.first(where: { !knownVariables.contains($0) }) {
            throw .unknownVariable(unknown)
        }
        guard variables.contains("url") else { throw .missingURL }

        let values = [
            "url": url.absoluteString,
            "title": title,
            "callback": callbackURL,
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
