import Foundation
@testable import Strimr
import Testing

@MainActor
struct JellyfinMetadataEditTests {
    private func data() throws -> Data {
        try Fixtures.data("jellyfin-editable-item")
    }

    private func dto() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data()) as? [String: Any])
    }

    private func loadDraft() throws -> MetadataDraft {
        try #require(JellyfinManagementService.metadataDraft(
            from: data(),
            fields: MetadataField.editableFields(for: .movie),
            contentRatingOptions: ["PG", "PG-13"],
        ))
    }

    @Test func `draft reads the fields and their locks`() throws {
        let draft = try loadDraft()

        #expect(draft.value(.title) == "Example Movie")
        #expect(draft.value(.releaseDate) == "2010-07-16")
        #expect(draft.value(.studio) == "Example Studio")
        #expect(draft.value(.tagline) == "An example tagline.")
        #expect(draft.list(.directors) == ["Jane Doe"])
        #expect(draft.list(.writers) == ["John Doe"])
        #expect(draft.list(.labels) == ["Favorites"])
        #expect(draft.lockedFields == [.title])
        #expect(!draft.lockableFields.contains(.sortTitle))
        #expect(draft.contentRatingOptions == ["PG", "PG-13"])
    }

    @Test func `unedited keys are sent back unchanged`() throws {
        let original = try loadDraft()
        var draft = original
        draft.setValue("New summary", for: .summary)

        let updated = try JellyfinManagementService.updatedItem(dto(), draft: draft, original: original)

        #expect(updated["Overview"] as? String == "New summary")
        #expect(updated["Name"] as? String == "Example Movie")
        #expect(updated["OfficialRating"] as? String == "PG-13")
        #expect(updated["ProviderIds"] as? [String: String] == ["Tmdb": "1"])
        #expect(updated["Genres"] as? [String] == ["Action", "Science Fiction"])
        #expect((updated["People"] as? [[String: Any]])?.count == 3)
        #expect(updated["Trickplay"] == nil)
    }

    @Test func `locked fields keep the unknown ones and add the edited ones`() throws {
        let original = try loadDraft()
        var draft = original
        draft.setValue("New summary", for: .summary)
        draft.setLocked(false, for: .title)
        draft.addListEntry("Lee Doe", to: .directors)

        let updated = try JellyfinManagementService.updatedItem(dto(), draft: draft, original: original)

        #expect(updated["LockedFields"] as? [String] == ["Runtime", "Overview", "Cast"])
    }

    @Test func `people of other types and known details are kept`() throws {
        let original = try loadDraft()
        var draft = original
        draft.setList(["Jane Doe", "Lee Doe"], for: .directors)

        let updated = try JellyfinManagementService.updatedItem(dto(), draft: draft, original: original)
        let people = try #require(updated["People"] as? [[String: Any]])

        #expect(people.map { $0["Name"] as? String } == ["John Doe", "Alex Doe", "Jane Doe", "Lee Doe"])
        #expect(people[2]["Id"] as? String == "person-1")
        #expect(people[3]["Type"] as? String == "Director")
    }

    @Test func `the date keeps the stored time and updates the year`() throws {
        let original = try loadDraft()
        var draft = original
        draft.setValue("2012-03-01", for: .releaseDate)

        let updated = try JellyfinManagementService.updatedItem(dto(), draft: draft, original: original)

        #expect(updated["PremiereDate"] as? String == "2012-03-01T04:00:00.0000000Z")
        #expect(updated["ProductionYear"] as? Int == 2012)
    }

    @Test func `studio and tagline replace only the first entry`() throws {
        let original = try loadDraft()
        var draft = original
        draft.setValue("Other Studio", for: .studio)
        draft.setValue("", for: .tagline)

        let updated = try JellyfinManagementService.updatedItem(dto(), draft: draft, original: original)

        #expect((updated["Studios"] as? [[String: Any]])?.map { $0["Name"] as? String }
            == ["Other Studio", "Second Studio"])
        #expect(updated["Taglines"] as? [String] == ["Another tagline."])
    }

    @Test func `cleared text fields are sent empty`() throws {
        let original = try loadDraft()
        var draft = original
        draft.setValue("", for: .originalTitle)

        let updated = try JellyfinManagementService.updatedItem(dto(), draft: draft, original: original)

        #expect(updated["OriginalTitle"] is NSNull)
    }
}
