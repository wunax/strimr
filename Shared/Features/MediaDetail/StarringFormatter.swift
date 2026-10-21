import Foundation

enum StarringFormatter {
    /// "Starring A, B, C" from the first billed cast members; nil when no name is known.
    static func text(from cast: [CastMember], limit: Int = 3) -> String? {
        var seen = Set<String>()
        let names = cast
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(limit)
        guard !names.isEmpty else { return nil }
        return String(localized: "media.detail.starring \(names.joined(separator: ", "))")
    }
}
