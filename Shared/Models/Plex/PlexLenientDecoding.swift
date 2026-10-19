import Foundation

/// Plex JSON is converted from XML, so a scalar attribute can arrive as a string, a number or a 0/1 flag
/// depending on the endpoint and the server version.
nonisolated protocol PlexLenientDecodable: Codable, Equatable, Sendable {
    static func lenientDecode(from container: SingleValueDecodingContainer) -> Self?
}

nonisolated extension Bool: PlexLenientDecodable {
    static func lenientDecode(from container: SingleValueDecodingContainer) -> Bool? {
        if let value = try? container.decode(Bool.self) {
            return value
        }
        if let value = try? container.decode(Int.self) {
            return value != 0
        }
        if let value = try? container.decode(String.self) {
            return ["1", "true"].contains(value.lowercased())
        }
        return nil
    }
}

nonisolated extension String: PlexLenientDecodable {
    static func lenientDecode(from container: SingleValueDecodingContainer) -> String? {
        if let value = try? container.decode(String.self) {
            return value
        }
        if let value = try? container.decode(Int.self) {
            return String(value)
        }
        if let value = try? container.decode(Double.self) {
            return String(value)
        }
        return nil
    }
}

nonisolated struct PlexLenient<Value: PlexLenientDecodable>: Codable, Equatable, Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let value = Value.lenientDecode(from: container) else {
            throw DecodingError.typeMismatch(
                Value.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported Plex value."),
            )
        }
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

nonisolated extension KeyedDecodingContainer {
    /// Drops the elements that fail to decode so one malformed item doesn't fail the whole Plex response.
    func decodeLossyArrayIfPresent<Element: Decodable>(_: Element.Type, forKey key: Key) throws -> [Element]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }

        var container = try nestedUnkeyedContainer(forKey: key)
        var elements: [Element] = []
        var firstError: Error?
        while !container.isAtEnd {
            do {
                try elements.append(container.decode(Element.self))
            } catch {
                firstError = firstError ?? error
                _ = try container.decode(SkippedElement.self)
            }
        }

        if let firstError {
            Task { @MainActor in ErrorReporter.capture(firstError) }
        }
        return elements
    }
}

/// Decoding it always succeeds, which moves an unkeyed container past a malformed element.
private nonisolated struct SkippedElement: Decodable {
    init(from _: Decoder) throws {}
}
