import Foundation

struct Hub: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [MediaItem]

    var hasItems: Bool {
        !items.isEmpty
    }
}
