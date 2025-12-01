import Foundation
import Observation

@MainActor
@Observable
final class LibraryRecommendedViewModel {
    let library: Library
    var hubs: [Hub] = []
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let plexApiManager: PlexAPIManager

    init(library: Library, plexApiManager: PlexAPIManager) {
        self.library = library
        self.plexApiManager = plexApiManager
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
            resetState(error: "Missing library identifier.")
            return
        }
        guard let api = plexApiManager.server else {
            resetState(error: "Select a server to load recommendations.")
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await api.getSectionHubs(sectionId: sectionId)
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
