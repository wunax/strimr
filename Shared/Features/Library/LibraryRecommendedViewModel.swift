import Foundation
import Observation

@MainActor
@Observable
final class LibraryRecommendedViewModel {
    let library: Library
    var hubs: [Hub] = []
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let service: any MediaLibraryService
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(library: Library, services: MediaServices) {
        self.library = library
        service = services.library
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            hubs = try await service.recommended(in: library)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
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
