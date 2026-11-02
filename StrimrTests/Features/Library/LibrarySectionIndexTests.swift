@testable import Strimr
import Testing

struct LibrarySectionIndexTests {
    private func makeIndex(_ characters: [(String, Int)]) -> LibrarySectionIndex {
        LibrarySectionIndex(characters: characters.map { PlexAdvancedSectionCharacter(title: $0.0, size: $0.1) })
    }

    private func titles(_ index: LibrarySectionIndex) -> [String] {
        index.sections.map(\.title)
    }

    @Test func `start indexes add up the sizes`() {
        let index = makeIndex([("#", 1), ("A", 7), ("B", 5)])

        #expect(index.sections.map(\.startIndex) == [0, 1, 8])
        #expect(index.sections.map(\.size) == [1, 7, 5])
    }

    @Test func `empty characters are left out`() {
        let index = makeIndex([("A", 2), ("B", 0), ("C", 1)])

        #expect(titles(index) == ["A", "C"])
        #expect(index.sections.last?.startIndex == 2)
    }

    @Test func `a single section is not usable`() {
        #expect(!makeIndex([("#", 125)]).isUsable)
        #expect(makeIndex([("A", 1), ("B", 1)]).isUsable)
    }

    @Test func `removing an item in the middle shifts the following sections`() {
        let index = makeIndex([("A", 3), ("B", 2), ("C", 4)]).removingIndexes([1])

        #expect(index.sections.map(\.size) == [2, 2, 4])
        #expect(index.sections.map(\.startIndex) == [0, 2, 4])
    }

    @Test func `removing every item of a section drops it`() {
        let index = makeIndex([("A", 2), ("B", 2), ("C", 1)]).removingIndexes([2, 3])

        #expect(titles(index) == ["A", "C"])
        #expect(index.sections.map(\.startIndex) == [0, 2])
    }

    @Test func `removing the last section keeps the others`() {
        let index = makeIndex([("A", 2), ("B", 1)]).removingIndexes([2])

        #expect(titles(index) == ["A"])
    }

    @Test func `section containing finds the edges`() {
        let index = makeIndex([("A", 3), ("B", 2)])

        #expect(index.section(containing: 0)?.title == "A")
        #expect(index.section(containing: 2)?.title == "A")
        #expect(index.section(containing: 3)?.title == "B")
        #expect(index.section(containing: 4)?.title == "B")
        #expect(index.section(containing: 5) == nil)
        #expect(index.section(containing: -1) == nil)
    }

    @Test func `typed letter jumps to its section`() {
        let index = makeIndex([("#", 1), ("A", 1), ("M", 1), ("S", 1)])

        #expect(index.section(forTypedCharacter: "M")?.title == "M")
        #expect(index.section(forTypedCharacter: "m")?.title == "M")
        #expect(index.section(forTypedCharacter: "É")?.title == "M")
        #expect(index.section(forTypedCharacter: "à")?.title == "A")
    }

    @Test func `missing letter jumps to the next one`() {
        let index = makeIndex([("A", 1), ("M", 1), ("S", 1)])

        #expect(index.section(forTypedCharacter: "B")?.title == "M")
        #expect(index.section(forTypedCharacter: "Z")?.title == "S")
    }

    @Test func `digits jump to the number section`() {
        let withNumbers = makeIndex([("#", 1), ("A", 1)])
        let withoutNumbers = makeIndex([("A", 1), ("B", 1)])

        #expect(withNumbers.section(forTypedCharacter: "7")?.title == "#")
        #expect(withoutNumbers.section(forTypedCharacter: "7")?.title == "A")
    }

    @Test func `typed letter ignores a descending order`() {
        let index = makeIndex([("Z", 1), ("M", 1), ("A", 1), ("#", 1)])

        #expect(index.section(forTypedCharacter: "B")?.title == "M")
        #expect(index.section(forTypedCharacter: "Z")?.startIndex == 0)
        #expect(index.section(forTypedCharacter: "1")?.title == "#")
    }

    @Test func `compact entries keep every section when they fit`() {
        let index = makeIndex([("A", 1), ("B", 1), ("C", 1)])

        #expect(index.compactEntries(fitting: 3) == index.sections.map(LibrarySectionIndex.CompactEntry.section))
    }

    @Test func `compact entries fit the slots and cover every section once`() {
        let letters = ["#"] + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        let index = makeIndex(letters.map { ($0, 1) })

        let entries = index.compactEntries(fitting: 13)
        let covered = entries.flatMap { entry -> [String] in
            switch entry {
            case let .section(section): [section.title]
            case let .collapsed(sections): sections.map(\.title)
            }
        }

        #expect(entries.count <= 13)
        #expect(covered == letters)
        #expect(entries.first == .section(index.sections[0]))
        #expect(entries.last == .section(index.sections[26]))
    }
}
