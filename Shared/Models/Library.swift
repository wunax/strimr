import Foundation

struct Library: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let type: MediaKind
    let sectionId: Int?

    var iconName: String {
        switch type {
        case .movie:
            "film.fill"
        case .series:
            "tv.fill"
        case .season, .episode:
            "play.rectangle.fill"
        case .collection:
            "rectangle.stack.fill"
        case .playlist:
            "music.note.list"
        case .folder, .unknown:
            "questionmark.square.fill"
        }
    }

    init(
        id: String,
        title: String,
        type: MediaKind,
        sectionId: Int? = nil,
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.sectionId = sectionId
    }
}

extension Library {
    init(plexSection: PlexSection) {
        self.init(
            id: plexSection.key,
            title: plexSection.title,
            type: plexSection.type.mediaKind,
            sectionId: Int(plexSection.key),
        )
    }
}
