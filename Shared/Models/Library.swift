import Foundation

struct Library: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let title: String
    let type: MediaKind
    let sectionId: Int?
    private(set) var server: ServerIdentity

    var identity: LibraryIdentity {
        LibraryIdentity(server: server, libraryID: id)
    }

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
        case .clip:
            "play.rectangle.fill"
        case .folder, .unknown:
            "questionmark.square.fill"
        }
    }

    init(
        id: String,
        title: String,
        type: MediaKind,
        sectionId: Int? = nil,
        server: ServerIdentity,
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.sectionId = sectionId
        self.server = server
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(MediaKind.self, forKey: .type)
        sectionId = try container.decodeIfPresent(Int.self, forKey: .sectionId)
        server = try container.decodeIfPresent(ServerIdentity.self, forKey: .server) ?? .unassigned
    }

    func assigning(server: ServerIdentity) -> Library {
        var library = self
        library.server = server
        return library
    }
}

extension Library {
    init(plexSection: PlexSection, server: ServerIdentity) {
        self.init(
            id: plexSection.key,
            title: plexSection.title,
            type: plexSection.type.mediaKind,
            sectionId: Int(plexSection.key),
            server: server,
        )
    }
}
