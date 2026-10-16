import Foundation

nonisolated enum ExternalPlayerTemplateError: Error, Equatable {
    case missingURL
    case unknownVariable(String)
    case misplacedListVariable(String)
    case invalidURL
}

/// Builds a player URL from a template such as `myplayer://play?url={url}`.
nonisolated enum ExternalPlayerTemplate {
    private static let knownVariables: Set<String> = ["url", "title", "position", "callback", "subtitles"]
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

        let expanded = try expandingLists(in: template, lists: [
            "subtitles": target.subtitles.map(\.absoluteString),
        ])
        let values = [
            "url": target.url.absoluteString,
            "title": target.title,
            "position": String(Int(max(0, target.startPosition))),
            "callback": ExternalPlaybackCallback.url(for: target).absoluteString,
        ]
        let rendered = expanded.replacing(variablePattern) { match in
            encode(values[String(match.output.1)] ?? "")
        }
        guard let result = URL(string: rendered), let scheme = result.scheme, !scheme.isEmpty else {
            throw .invalidURL
        }
        return result
    }

    /// A list variable must be a whole query value: its parameter is repeated for each item, and dropped when the
    /// list is empty, as in `sub={subtitles}`.
    private static func expandingLists(
        in template: String,
        lists: [String: [String]],
    ) throws(ExternalPlayerTemplateError) -> String {
        let placeholders = Dictionary(uniqueKeysWithValues: lists.map { ("{\($0.key)}", $0.value) })
        var base = template
        var parameters: [String] = []
        if let queryStart = template.firstIndex(of: "?") {
            base = String(template[..<queryStart])
            parameters = template[template.index(after: queryStart)...]
                .split(separator: "&", omittingEmptySubsequences: false)
                .flatMap { parameter -> [String] in
                    let parts = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count == 2, let items = placeholders[String(parts[1])] else {
                        return [String(parameter)]
                    }
                    return items.map { "\(parts[0])=\(encode($0))" }
                }
        }
        let remaining = ([base] + parameters).joined(separator: "&")
        if let misplaced = lists.keys.sorted().first(where: { remaining.contains("{\($0)}") }) {
            throw .misplacedListVariable(misplaced)
        }
        return parameters.isEmpty ? base : "\(base)?\(parameters.joined(separator: "&"))"
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowedValueCharacters) ?? ""
    }
}
