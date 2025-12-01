import Foundation

struct Library: Identifiable, Equatable {
    let id: String
    let title: String
    let type: PlexItemType
    let sectionId: Int?

    var iconName: String {
        switch type {
        case .movie:
            return "film.fill"
        case .show:
            return "tv.fill"
        case .season, .episode:
            return "play.rectangle.fill"
        }
    }

    init(
        id: String,
        title: String,
        type: PlexItemType,
        sectionId: Int? = nil
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
            type: plexSection.type,
            sectionId: Int(plexSection.key)
        )
    }
}
