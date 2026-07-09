import Foundation

struct Hub: Identifiable, Hashable {
    let id: String
    let key: String
    let hubKey: String?
    let title: String
    let size: Int
    let more: Bool?
    let items: [MediaDisplayItem]

    var hasItems: Bool {
        !items.isEmpty
    }

    var hasMoreItems: Bool {
        more == true
    }

    var canOpenDetail: Bool {
        PlexEndpoint(key: key) != nil
    }

    var canShowViewAll: Bool {
        hasMoreItems && canOpenDetail
    }
}
