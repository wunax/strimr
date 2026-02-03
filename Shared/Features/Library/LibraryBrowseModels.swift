import Foundation

struct LibraryBrowseFolderItem: Identifiable, Equatable {
    let id: String
    let key: String
    let title: String
}

enum LibraryBrowseItem: Identifiable, Equatable {
    case media(MediaDisplayItem)
    case folder(LibraryBrowseFolderItem)

    var id: String {
        switch self {
        case let .media(item):
            item.id
        case let .folder(item):
            item.id
        }
    }
}
