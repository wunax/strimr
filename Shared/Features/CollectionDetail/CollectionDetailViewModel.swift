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
        guard items.isEmpty else { return }
        await fetch()
    }

    private func fetch() async {
        guard let collectionsRepository = try? CollectionRepository(context: context) else {
            errorMessage = String(localized: "errors.selectServer.loadDetails")
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await collectionsRepository.getCollectionChildren(ratingKey: collection.id)
            items = (response.mediaContainer.metadata ?? []).compactMap(MediaDisplayItem.init)
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }
}
