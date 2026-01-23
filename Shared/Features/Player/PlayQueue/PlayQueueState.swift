import Foundation

struct PlayQueueState: Equatable {
    let id: Int
    let selectedItemID: Int?
    let selectedMetadataItemID: String?
    let totalCount: Int?
    let version: Int?
    let shuffled: Bool?
    let sourceURI: String?
    let items: [PlexItem]

    init(response: PlexPlayQueueResponse) {
        let container = response.mediaContainer
        id = container.playQueueID
        selectedItemID = container.playQueueSelectedItemID
        selectedMetadataItemID = container.playQueueSelectedMetadataItemID
        totalCount = container.playQueueTotalCount
        version = container.playQueueVersion
        shuffled = container.playQueueShuffled
        sourceURI = container.playQueueSourceURI
        items = container.metadata ?? []
    }

    var selectedRatingKey: String? {
        if let selectedMetadataItemID {
            return selectedMetadataItemID
        }
        if let selectedItemID {
            return items.first { $0.playQueueItemID == selectedItemID }?.ratingKey
        }
        return items.first?.ratingKey
    }

    func item(after ratingKey: String) -> PlexItem? {
        guard let index = items.firstIndex(where: { $0.ratingKey == ratingKey }) else { return nil }
        let nextIndex = items.index(after: index)
        guard nextIndex < items.endIndex else { return nil }
        return items[nextIndex]
    }
}
