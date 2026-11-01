import Foundation
@testable import Strimr
import Testing

@MainActor
struct ArtworkPickerViewModelTests {
    private struct Failure: LocalizedError {
        var errorDescription: String? {
            "Provider unavailable"
        }
    }

    private final class Service: MediaManagementService {
        var failingKinds: Set<EditableArtworkKind> = []

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
            [.poster, .logo]
        }

        func artworkOptions(for _: MediaItem, kind: EditableArtworkKind) async throws -> [ArtworkOption] {
            if failingKinds.contains(kind) {
                throw Failure()
            }
            return [ArtworkOption(
                id: kind.rawValue,
                previewURL: URL(string: "https://images.test/\(kind.rawValue).jpg")!,
                source: kind.rawValue,
                provider: nil,
                width: nil,
                height: nil,
                language: nil,
                isSelected: false,
            )]
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
    }

    @Test func `returning to a loaded kind clears the error of a failed one`() async {
        let service = Service()
        service.failingKinds = [.logo]
        let item = MediaItem.make(id: "item", server: ServerIdentity(provider: .plex, id: "server"))
        let viewModel = ArtworkPickerViewModel(item: item, kinds: [.poster, .logo], service: service) { _ in }

        await viewModel.load()
        viewModel.selectedKind = .logo
        await viewModel.load()
        #expect(viewModel.errorMessage == "Provider unavailable")

        viewModel.selectedKind = .poster
        await viewModel.load()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.visibleOptions.map(\.id) == ["poster"])
    }
}
