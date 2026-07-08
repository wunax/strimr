import Foundation
import Observation

@MainActor
@Observable
final class CollectionDetailViewModel {
    @ObservationIgnored private let context: PlexAPIContext

    var collection: CollectionMediaItem
    var items: [MediaDisplayItem] = []
    var isLoading = false
    var errorMessage: String?
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(collection: CollectionMediaItem, context: PlexAPIContext) {
        self.collection = collection
        self.context = context
    }

    var collectionDisplayItem: MediaDisplayItem {
        .collection(collection)
    }

    var elementsCountText: String? {
        guard let childCount = collection.childCount else { return nil }
        return String(localized: "media.labels.elementsCount \(childCount)")
    }

    var yearsText: String? {
        switch (collection.minYear, collection.maxYear) {
        case let (min?, max?) where min != max:
            "\(min) - \(max)"
        case let (min?, _):
            min
        case let (_, max?):
            max
        default:
            nil
        }
    }

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await reload()
    }

    func reload() async {
        await fetch(preservingExistingContent: false)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading) else { return }
        await fetch(preservingExistingContent: true)
    }

    private func fetch(preservingExistingContent: Bool) async {
        guard let collectionsRepository = try? CollectionRepository(context: context) else {
            handleLoadError(
                String(localized: "errors.selectServer.loadDetails"),
                preservingExistingContent: preservingExistingContent,
            )
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await collectionsRepository.getCollectionChildren(ratingKey: collection.id)
            items = (response.mediaContainer.metadata ?? []).compactMap(MediaDisplayItem.init)
        } catch {
            handleLoadError(error.localizedDescription, preservingExistingContent: preservingExistingContent)
        }
    }

    private func handleLoadError(_ message: String, preservingExistingContent: Bool) {
        if preservingExistingContent, !items.isEmpty {
            errorMessage = nil
            isLoading = false
        } else {
            items = []
            errorMessage = message
            isLoading = false
        }
    }
}
