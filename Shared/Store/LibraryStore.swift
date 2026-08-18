import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    var libraries: [Library] = []
    var isLoading = false
    var loadFailed = false

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private var service: (any MediaLibraryService)?

    init(context: PlexAPIContext) {
        self.context = context
    }

    func configure(service: (any MediaLibraryService)?) {
        self.service = service
        libraries = []
        loadFailed = false
    }

    func loadLibraries() async throws {
        guard !isLoading else { return }
        guard libraries.isEmpty else { return }

        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        do {
            if let service {
                libraries = try await service.libraries()
                return
            }
            let repository = try SectionRepository(context: context)
            let response = try await repository.getSections()
            let sections = response.mediaContainer.directory ?? []
            libraries = sections
                .filter(\.type.isSupported)
                .map(Library.init)
        } catch {
            loadFailed = true
            throw error
        }
    }

    func reloadLibraries() async throws {
        libraries = []
        try await loadLibraries()
    }
}
