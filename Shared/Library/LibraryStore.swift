import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    var libraries: [Library] = []
    var isLoading = false
    var loadFailed = false

    @ObservationIgnored private let context: PlexAPIContext

    init(context: PlexAPIContext) {
        self.context = context
    }

    func loadLibraries() async throws {
        guard !isLoading else { return }
        guard libraries.isEmpty else { return }

        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        do {
            let repository = try SectionRepository(context: context)
            let response = try await repository.getSections()
            let sections = response.mediaContainer.directory ?? []
            libraries = sections.map(Library.init)
        } catch {
            loadFailed = true
            throw error
        }
    }
}
