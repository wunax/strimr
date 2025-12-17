import Foundation
import Observation

@MainActor
@Observable
final class LibraryRecommendedViewModel {
    let library: Library
    var hubs: [Hub] = []
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let context: PlexAPIContext

    init(library: Library, context: PlexAPIContext) {
        self.library = library
        self.context = context
    }

    var hasContent: Bool {
        hubs.contains(where: \.hasItems)
    }

    func load() async {
        guard hubs.isEmpty else { return }
        await fetchHubs()
    }

    private func fetchHubs() async {
        guard let sectionId = library.sectionId else {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        guard let hubRepository = try? HubRepository(context: context) else {
            resetState(error: String(localized: "errors.selectServer.loadRecommendations"))
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await hubRepository.getSectionHubs(sectionId: sectionId)
            let plexHubs = response.mediaContainer.hub
            hubs = plexHubs.map(Hub.init)
        } catch {
            resetState(error: error.localizedDescription)
        }
    }

    private func resetState(error: String? = nil) {
        hubs = []
        errorMessage = error
        isLoading = false
    }
}
