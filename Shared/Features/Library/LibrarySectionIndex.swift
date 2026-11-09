import Foundation

/// Where each first character starts in a listing sorted by title, as Plex's `firstCharacter` endpoint reports it.
nonisolated struct LibrarySectionIndex: Equatable {
    struct Section: Identifiable, Hashable {
        let id: String
        let title: String
        let size: Int
        let startIndex: Int
    }

    enum CompactEntry: Hashable {
        case section(Section)
        /// Sections hidden to fit the available height, drawn as a dot.
        case collapsed([Section])

        var firstSection: Section? {
            switch self {
            case let .section(section): section
            case let .collapsed(sections): sections.first
            }
        }
    }

    /// Fewer sections leave nothing to jump between; Plex answers a single `#` section for non-title sorts.
    static let minimumSectionCount = 2

    let sections: [Section]

    init(sections: [Section]) {
        self.sections = sections
    }

    init(characters: [PlexAdvancedSectionCharacter]) {
        var runningIndex = 0
        sections = characters.compactMap { character in
            guard character.size > 0 else { return nil }
            defer { runningIndex += character.size }
            return Section(
                id: "\(character.title)-\(runningIndex)",
                title: character.title,
                size: character.size,
                startIndex: runningIndex,
            )
        }
    }

    var isUsable: Bool {
        sections.count >= Self.minimumSectionCount
    }

    /// Removed indexes are those before the shift; sections left empty are dropped.
    func removingIndexes(_ removed: [Int]) -> LibrarySectionIndex {
        guard !removed.isEmpty else { return self }
        var runningIndex = 0
        return LibrarySectionIndex(sections: sections.compactMap { section in
            let end = section.startIndex + section.size
            let size = section.size - removed.count(where: { $0 >= section.startIndex && $0 < end })
            guard size > 0 else { return nil }
            defer { runningIndex += size }
            return Section(
                id: "\(section.title)-\(runningIndex)",
                title: section.title,
                size: size,
                startIndex: runningIndex,
            )
        })
    }

    func section(containing index: Int) -> Section? {
        guard index >= 0 else { return nil }
        return sections.last { $0.startIndex <= index && index < $0.startIndex + $0.size }
    }

    /// Like the Finder: a missing letter jumps to the next one in the alphabet, whatever the sort direction.
    func section(forTypedCharacter character: Character) -> Section? {
        let key = Self.indexKey(for: String(character))
        let ordered = sections.sorted { Self.indexKey(for: $0.title) < Self.indexKey(for: $1.title) }
        return ordered.first { Self.indexKey(for: $0.title) >= key } ?? ordered.last
    }

    /// Plex files accented titles under the bare letter and everything that is not a letter under `#`.
    static func indexKey(for text: String) -> String {
        let folded = text.prefix(1)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .uppercased()
        guard let scalar = folded.unicodeScalars.first, CharacterSet.letters.contains(scalar) else { return "#" }
        return folded
    }

    /// Keeps the first and last sections and spreads the others evenly, replacing each hidden run with a dot.
    func compactEntries(fitting slots: Int) -> [CompactEntry] {
        guard sections.count > slots else { return sections.map(CompactEntry.section) }
        let visibleCount = max(2, (slots + 1) / 2)
        let lastIndex = sections.count - 1
        let visibleIndexes = (0 ..< visibleCount).map { position in
            Int((Double(position * lastIndex) / Double(visibleCount - 1)).rounded())
        }

        var entries: [CompactEntry] = []
        var previous: Int?
        for index in visibleIndexes where index != previous {
            if let previous, index - previous > 1 {
                entries.append(.collapsed(Array(sections[(previous + 1) ..< index])))
            }
            entries.append(.section(sections[index]))
            previous = index
        }
        return entries
    }
}
