import Foundation
@testable import Strimr
import Testing

struct MetadataEditModelsTests {
    private func makeDraft(lockable: Set<MetadataField>? = nil) -> MetadataDraft {
        let fields = MetadataField.editableFields(for: .movie)
        return MetadataDraft(
            fields: fields,
            values: [.title: "Title"],
            lists: [.genres: ["Action"]],
            lockedFields: [],
            lockableFields: lockable ?? Set(fields),
            sharedLocks: [[.directors, .writers]],
            payload: .plex(sectionID: "1", type: 1),
        )
    }

    @Test func `editable fields depend on the type`() {
        #expect(MetadataField.editableFields(for: .movie) == MetadataField.allCases)
        #expect(!MetadataField.editableFields(for: .series).contains(.directors))
        #expect(MetadataField.editableFields(for: .episode)
            == [.title, .releaseDate, .summary, .directors, .writers])
        #expect(MetadataField.editableFields(for: .season).isEmpty)
    }

    @Test func `editing a field locks it when the server can`() {
        var draft = makeDraft(lockable: [.title])
        draft.setValue("New", for: .title)
        draft.setValue("Tagline", for: .tagline)

        #expect(draft.lockedFields == [.title])
        #expect(draft.changedFields(from: makeDraft()) == [.title, .tagline])
    }

    @Test func `setting the same value changes nothing`() {
        var draft = makeDraft()
        draft.setValue("Title", for: .title)

        #expect(!draft.hasChanges(from: makeDraft()))
    }

    @Test func `shared locks change together`() {
        var draft = makeDraft()
        draft.setLocked(true, for: .directors)
        #expect(draft.lockedFields == [.directors, .writers])

        draft.setLocked(false, for: .writers)
        #expect(draft.lockedFields.isEmpty)
    }

    @Test func `a lock changed alone is a change of its own`() {
        var draft = makeDraft()
        draft.setLocked(true, for: .summary)

        #expect(draft.changedFields(from: makeDraft()).isEmpty)
        #expect(draft.lockChangedFields(from: makeDraft()) == [.summary])
        #expect(draft.hasChanges(from: makeDraft()))
    }

    @Test func `list entries are trimmed and not duplicated`() {
        var draft = makeDraft()
        draft.addListEntry("  Drama ", to: .genres)
        draft.addListEntry("action", to: .genres)
        draft.addListEntry(" ", to: .genres)

        #expect(draft.list(.genres) == ["Action", "Drama"])
        #expect(draft.isLocked(.genres))
    }

    @Test func `dates round-trip as calendar days`() throws {
        let date = try #require(MetadataDate.date(from: "2010-07-16"))

        #expect(MetadataDate.string(from: date) == "2010-07-16")
        #expect(MetadataDate.date(from: "") == nil)
    }
}
