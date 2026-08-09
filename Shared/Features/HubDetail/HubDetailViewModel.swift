import Foundation
import Observation

@MainActor
@Observable
final class HubDetailViewModel {
    let hub: Hub
    var items: [MediaDisplayItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?

    @ObservationIgnored private let service: any MediaHomeService
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var reachedEnd = false
    @ObservationIgnored private var totalItemCount: Int?
    @ObservationIgnored private let pageSize = 50

    init(hub: Hub, services: MediaServices) {
        self.hub = hub
        service = services.home
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        items = []
        reachedEnd = false
        totalItemCount = nil
        await loadPage(start: 0, isInitialLoad: true)
    }

    func loadMoreIfNeeded(currentItem item: MediaDisplayItem) async {
        guard item.id == items.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !items.isEmpty else { return }
        await loadPage(start: items.count, isInitialLoad: false)
    }

    private func loadPage(start: Int, isInitialLoad: Bool) async {
        guard !reachedEnd else { return }
        guard !isLoading, !isLoadingMore else { return }

        if isInitialLoad {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil
        defer {
            if isInitialLoad {
                isLoading = false
            } else {
                isLoadingMore = false
            }
        }

        do {
            let response = try await service.items(in: hub, startIndex: start, limit: pageSize)
            let newItems = response.items
            totalItemCount = response.totalCount ?? totalItemCount

            if isInitialLoad {
                items = newItems
            } else {
                items.append(contentsOf: newItems)
            }

            if newItems.isEmpty {
                reachedEnd = true
            } else if let totalItemCount {
                reachedEnd = items.count >= totalItemCount
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = String(localized: "hub.error.loadFailed")
            if isInitialLoad {
                items = []
            }
        }
    }
}
