import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlexMetadataEditTests {
    private func loadDraft() throws -> MetadataDraft {
        let response = try Fixtures.decode(PlexEditableMetadataResponse.self, from: "plex-editable-metadata")
        let metadata = try #require(response.mediaContainer.metadata?.first)
        return PlexManagementService.metadataDraft(
            from: metadata,
            fields: MetadataField.editableFields(for: .movie),
            sectionID: "3",
            type: 1,
        )
    }

    private func query(_ items: [URLQueryItem]) -> [String: String] {
        Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }

    @Test func `draft reads the fields and their locks`() throws {
        let draft = try loadDraft()

        #expect(draft.value(.title) == "Example Movie")
        #expect(draft.value(.sortTitle) == "Movie, Example")
        #expect(draft.value(.releaseDate) == "2010-07-16")
        #expect(draft.list(.genres) == ["Action", "Science Fiction"])
        #expect(draft.list(.labels) == ["Favorites"])
        #expect(draft.list(.directors) == ["Jane Doe"])
        #expect(draft.lockedFields == [.title, .genres])
        #expect(draft.lockableFields == Set(MetadataField.allCases))
    }

    @Test func `only changed fields are sent, and locked`() throws {
        let original = try loadDraft()
        var draft = original
        draft.setValue("A summary", for: .summary)

        let requests = PlexManagementService.metadataUpdates(draft, original: original, itemID: "100", type: 1)

        #expect(requests.count == 1)
        #expect(query(requests[0]) == [
            "type": "1",
            "id": "100",
            "summary.value": "A summary",
            "summary.locked": "1",
        ])
    }

    @Test func `tags restate the kept ones and remove the others`() throws {
        let original = try loadDraft()
        var draft = original
        draft.setList(["Science Fiction", "Drama"], for: .genres)

        let requests = PlexManagementService.metadataUpdates(draft, original: original, itemID: "100", type: 1)

        #expect(requests.count == 1)
        #expect(query(requests[0]) == [
            "type": "1",
            "id": "100",
            "genre[0].tag.tag": "Science Fiction",
            "genre[1].tag.tag": "Drama",
            "genre[].tag.tag-": "Action",
            "genre.locked": "1",
        ])
    }

    @Test func `a removed tag with a comma gets its own request`() throws {
        let original = try loadDraft()
        var start = original
        start.setList(["Action", "Kids, Family"], for: .genres)
        var draft = start
        draft.setList([], for: .genres)

        let requests = PlexManagementService.metadataUpdates(draft, original: start, itemID: "100", type: 1)

        #expect(requests.count == 3)
        #expect(query(requests[0])["genre[].tag.tag-"] == nil)
        #expect(requests.dropFirst().map { query($0)["genre[].tag.tag-"] } == ["Action", "Kids, Family"])
    }

    @Test func `unlocking a field sends its lock alone`() throws {
        let original = try loadDraft()
        var draft = original
        draft.setLocked(false, for: .title)

        let requests = PlexManagementService.metadataUpdates(draft, original: original, itemID: "100", type: 1)

        #expect(query(requests[0]) == ["type": "1", "id": "100", "title.locked": "0"])
    }

    @Test func `edit types match the Plex metadata types`() {
        #expect(PlexManagementService.metadataType(for: .movie) == 1)
        #expect(PlexManagementService.metadataType(for: .series) == 2)
        #expect(PlexManagementService.metadataType(for: .episode) == 4)
        #expect(PlexManagementService.metadataType(for: .season) == nil)
    }
}
