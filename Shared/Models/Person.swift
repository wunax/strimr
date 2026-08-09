import Foundation

struct Person: Identifiable, Hashable {
    let id: String
    let name: String
    let thumbPath: String?

    init(id: String, name: String, thumbPath: String?) {
        self.id = id
        self.name = name
        self.thumbPath = thumbPath
    }

    init(directory: PlexPersonDirectory) {
        id = String(directory.id)
        name = directory.tag
        thumbPath = directory.thumb
    }
}
