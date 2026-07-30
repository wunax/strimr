import Foundation

struct Person: Identifiable, Hashable {
    let id: Int
    let name: String
    let thumbPath: String?

    init(id: Int, name: String, thumbPath: String?) {
        self.id = id
        self.name = name
        self.thumbPath = thumbPath
    }

    init(directory: PlexPersonDirectory) {
        id = directory.id
        name = directory.tag
        thumbPath = directory.thumb
    }
}
