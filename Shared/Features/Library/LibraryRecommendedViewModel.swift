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
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(library: Library, context: PlexAPIContext) {
        self.library = library
        self.context = context
    }

    var hasContent: Bool {
        hubs.contains(where: \.hasItems)
    }

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await reload()
    }

    func reload() async {
        await fetchHubs(preservingExistingContent: false)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading) else { return }
        await fetchHubs(preservingExistingContent: true)
    }

    private func fetchHubs(preservingExistingContent: Bool) async {
        guard let sectionId = library.sectionId else {
            handleLoadError(
                String(localized: "errors.missingLibraryIdentifier"),
                preservingExistingContent: preservingExistingContent,
            )
            return
        }
        guard let hubRepository = try? HubRepository(context: context) else {
            handleLoadError(
                String(localized: "errors.selectServer.loadRecommendations"),
                preservingExistingContent: preservingExistingContent,
            )
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await hubRepository.getSectionHubs(sectionId: sectionId)
            let plexHubs = response.mediaContainer.hub ?? []
            hubs = plexHubs.map(Hub.init)
        } catch {
            ErrorReporter.capture(error)
            handleLoadError(error.localizedDescription, preservingExistingContent: preservingExistingContent)
        }
    }

    private func resetState(error: String? = nil) {
        hubs = []
        errorMessage = error
        isLoading = false
    }

    private func handleLoadError(_ message: String, preservingExistingContent: Bool) {
        if preservingExistingContent, hasContent {
            errorMessage = nil
            isLoading = false
        } else {
            resetState(error: message)
        }
    }
}
