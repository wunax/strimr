import Foundation
@testable import Strimr
import Testing

@MainActor
struct ItemSettingsViewModelTests {
    private struct Failure: LocalizedError {
        var errorDescription: String? {
            "Server said no"
        }
    }

    private final class Service: MediaManagementService {
        var updates: [(id: String, value: String, itemID: String)] = []
        var updateError: Error?

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
            .files(count: 1, totalSize: nil)
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
            []
        }

        func loadMetadataDraft(for _: MediaItem) async throws -> MetadataDraft {
            throw CancellationError()
        }

        func saveMetadata(_: MetadataDraft, original _: MetadataDraft, for _: MediaItem) async throws {}

        func metadataSuggestions(for _: MetadataField, item _: MediaItem) async throws -> [String] {
            []
        }

        func supportsAdvancedSettings(for _: MediaItem) -> Bool {
            true
        }

        func advancedSettings(itemID _: String) async throws -> [ItemSetting] {
            [ItemSetting(
                id: "episodeSort",
                label: "Episode sorting",
                summary: nil,
                value: "-1",
                options: [.init(value: "-1", label: "Library default"), .init(value: "1", label: "Newest first")],
            )]
        }

        func updateAdvancedSetting(_ setting: ItemSetting, value: String, itemID: String) async throws {
            if let updateError {
                throw updateError
            }
            updates.append((setting.id, value, itemID))
        }
    }

    private let item = MediaItem.make(id: "item", server: ServerIdentity(provider: .plex, id: "server"))

    @Test func `a choice is saved on the server and reported as a change`() async throws {
        let service = Service()
        var changes: [String] = []
        let viewModel = ItemSettingsViewModel(item: item, service: service) { changes.append($0) }
        await viewModel.load()
        let setting = try #require(viewModel.settings?.first)

        await viewModel.update(setting, to: "1")

        #expect(service.updates.map(\.value) == ["1"])
        #expect(service.updates.map(\.itemID) == ["item"])
        #expect(viewModel.settings?.first?.value == "1")
        #expect(viewModel.changeCount == 1)
        #expect(changes == ["item"])
    }

    @Test func `choosing the current value sends nothing`() async throws {
        let service = Service()
        let viewModel = ItemSettingsViewModel(item: item, service: service) { _ in }
        await viewModel.load()
        let setting = try #require(viewModel.settings?.first)

        await viewModel.update(setting, to: "-1")

        #expect(service.updates.isEmpty)
        #expect(viewModel.changeCount == 0)
    }

    @Test func `a failed choice keeps the previous value`() async throws {
        let service = Service()
        service.updateError = Failure()
        let viewModel = ItemSettingsViewModel(item: item, service: service) { _ in }
        await viewModel.load()
        let setting = try #require(viewModel.settings?.first)

        await viewModel.update(setting, to: "1")

        #expect(viewModel.settings?.first?.value == "-1")
        #expect(viewModel.failure?.message == "Server said no")
        #expect(viewModel.changeCount == 0)
    }

    @Test func `a refusal explains the missing right`() async throws {
        let service = Service()
        service.updateError = PlexAPIError.requestFailed(statusCode: 403)
        let viewModel = ItemSettingsViewModel(item: item, service: service) { _ in }
        await viewModel.load()
        let setting = try #require(viewModel.settings?.first)

        await viewModel.update(setting, to: "1")

        #expect(viewModel.failure?.message == String(localized: "media.manage.error.forbidden"))
    }
}
