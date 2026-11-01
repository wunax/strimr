import Foundation

@MainActor
final class PlexManagementService: MediaManagementService {
    private let context: PlexAPIContext

    init(context: PlexAPIContext) {
        self.context = context
    }

    var supportsAnalyze: Bool {
        true
    }

    func refreshMetadata(itemID: String) async throws {
        try await LibraryManagementRepository(context: context).refreshMetadata(ratingKey: itemID)
    }

    func analyze(itemID: String) async throws {
        try await LibraryManagementRepository(context: context).analyze(ratingKey: itemID)
    }

    var supportsLibraryTrash: Bool {
        true
    }

    func scanLibrary(id: String) async throws {
        try await LibraryManagementRepository(context: context).scanSection(sectionID: id, force: false)
    }

    func refreshLibraryMetadata(id: String) async throws {
        try await LibraryManagementRepository(context: context).scanSection(sectionID: id, force: true)
    }

    func analyzeLibrary(id: String) async throws {
        try await LibraryManagementRepository(context: context).analyzeSection(sectionID: id)
    }

    func emptyLibraryTrash(id: String) async throws {
        try await LibraryManagementRepository(context: context).emptySectionTrash(sectionID: id)
    }
}
