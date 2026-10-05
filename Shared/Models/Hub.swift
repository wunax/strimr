import Foundation

struct Hub: Identifiable, Hashable, Codable {
    let id: String
    let key: String
    let hubKey: String?
    let title: String
    let size: Int
    let more: Bool?
    let items: [MediaDisplayItem]
    /// Server of a provider hub; `nil` for rows merged across servers.
    var server: ServerIdentity? = nil

    var hasItems: Bool {
        !items.isEmpty
    }

    var hasMoreItems: Bool {
        more == true
    }

    /// Rows merged across servers have no server to load more items from.
    var canOpenDetail: Bool {
        server != nil && PlexEndpoint(key: key) != nil
    }

    var canShowViewAll: Bool {
        hasMoreItems && canOpenDetail
    }
}
