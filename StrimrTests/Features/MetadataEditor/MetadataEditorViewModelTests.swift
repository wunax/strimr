import Foundation
@testable import Strimr
import Testing

@MainActor
struct MetadataEditorViewModelTests {
    private struct Failure: LocalizedError {
        var errorDescription: String? {
            "Server said no"
        }
    }

    private final class Service: MediaManagementService {
        var saved: [(draft: MetadataDraft, original: MetadataDraft)] = []
        var saveError: Error?

        var supportsAnalyze: Bool {
            false
        }

        var supportsLibraryTrash: Bool {
            false
        }

        func refreshMetadata(itemID _: String) async throws {}
        func analyze(itemID _: String) async throws {}
        func scanLibrary(id _: String) async throws {}
        func refreshLibraryMetadata(id _: String) async throws {}
        func analyzeLibrary(id _: String) async throws {}
        func emptyLibraryTrash(id _: String) async throws {}

        func artworkKinds(for _: MediaItem) -> [EditableArtworkKind] {
            []
        }

        func artworkOptions(for _: MediaItem, kind _: EditableArtworkKind) async throws -> [ArtworkOption] {
            []
        }

        func selectArtwork(_: ArtworkOption, for _: MediaItem, kind _: EditableArtworkKind) async throws {}
        func uploadArtwork(_: ArtworkUpload, for _: MediaItem, kind _: EditableArtworkKind) async throws {}

        func deletionImpact(of _: MediaItem) async throws -> MediaDeletionImpact {
            .files(count: 0, totalSize: nil)
        }

        func delete(_: MediaItem) async throws {}

        func searchMatches(for _: MediaItem, title _: String, year _: Int?) async throws -> [MatchCandidate] {
            []
        }

        func applyMatch(_: MatchCandidate, to _: MediaItem) async throws {}

        var supportsUnmatch: Bool {
            false
        }

        func unmatch(itemID _: String) async throws {}

        func editableMetadataFields(for _: MediaItem) -> [MetadataField] {
            [.title, .genres]
        }

        func loadMetadataDraft(for _: MediaItem) async throws -> MetadataDraft {
            MetadataDraft(
                fields: [.title, .genres],
                values: [.title: "Title"],
                lists: [.genres: ["Action"]],
                lockedFields: [],
                lockableFields: [.title, .genres],
                payload: .plex(sectionID: "1", type: 1),
            )
        }

        func saveMetadata(_ draft: MetadataDraft, original: MetadataDraft, for _: MediaItem) async throws {
            if let saveError {
                throw saveError
            }
            saved.append((draft, original))
        }

        func metadataSuggestions(for field: MetadataField, item _: MediaItem) async throws -> [String] {
            field == .genres ? ["Action", "Adventure", "Drama"] : []
        }

        func supportsAdvancedSettings(for _: MediaItem) -> Bool {
            false
        }

        func advancedSettings(itemID _: String) async throws -> [ItemSetting] {
            []
        }

        func updateAdvancedSetting(_: ItemSetting, value _: String, itemID _: String) async throws {}
    }

    private let item = MediaItem.make(id: "item", server: ServerIdentity(provider: .plex, id: "server"))

    @Test func `saving is offered only once something changed`() async {
        let viewModel = MetadataEditorViewModel(item: item, service: Service()) { _ in }
        await viewModel.load()
        #expect(!viewModel.canSave)

        viewModel.setValue("Other", for: .title)
        #expect(viewModel.canSave)

        viewModel.setValue(" ", for: .title)
        #expect(!viewModel.canSave)
    }

    @Test func `save sends the draft with the loaded version and notes the change`() async {
        let service = Service()
        var savedIDs: [String] = []
        let viewModel = MetadataEditorViewModel(item: item, service: service) { savedIDs.append($0) }
        await viewModel.load()
        viewModel.addEntry("Drama", to: .genres)

        #expect(await viewModel.save())

        #expect(service.saved.map { $0.original.list(.genres) } == [["Action"]])
        #expect(service.saved.map { $0.draft.list(.genres) } == [["Action", "Drama"]])
        #expect(savedIDs == ["item"])
        #expect(viewModel.changeCount == 1)
        #expect(!viewModel.hasChanges)
    }

    @Test func `a failed save keeps the changes`() async {
        let service = Service()
        service.saveError = Failure()
        let viewModel = MetadataEditorViewModel(item: item, service: service) { _ in }
        await viewModel.load()
        viewModel.setValue("Other", for: .title)

        #expect(await !viewModel.save())

        #expect(viewModel.failure?.message == "Server said no")
        #expect(viewModel.hasChanges)
    }

    @Test func `suggestions skip the entries already listed`() async {
        let viewModel = MetadataEditorViewModel(item: item, service: Service()) { _ in }
        await viewModel.load()

        #expect(viewModel.suggestions(for: .genres, matching: "a") == ["Adventure", "Drama"])
        #expect(viewModel.suggestions(for: .genres, matching: "").isEmpty)
    }
}
