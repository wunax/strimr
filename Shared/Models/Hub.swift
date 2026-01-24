import Foundation

struct Hub: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MediaDisplayItem]

    var hasItems: Bool {
        !items.isEmpty
    }
}
